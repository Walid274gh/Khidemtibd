// ══════════════════════════════════════════════════════════════════════════════
// IntentExtractorService — Pure Gemma4 reasoning, zero embeddings
//
// WHY NO EMBEDDINGS?
//   The original design fetched embedding vectors → searched Qdrant for examples
//   → passed those examples to Gemma4. This required a separate embedding model
//   (text-embedding-004) that is unreliable, adds latency, and costs extra API calls.
//
//   Gemma4 is a frontier reasoning model that natively understands Arabic, Darija,
//   French, and English.  The few-shot examples live directly in the system prompt
//   (chain-of-thought style), which is MORE effective than retrieved RAG examples
//   because the model sees them every time, not just when retrieval works.
//
// PORTABILITY:
//   This service depends only on IAiProvider.  Swap env var AI_PROVIDER=ollama
//   and the entire pipeline runs 100% locally with Gemma4 via Ollama — zero cost,
//   zero cloud, zero GPU required for the e2b/e4b variants.
// ══════════════════════════════════════════════════════════════════════════════

import { Inject, Injectable, Logger, Optional } from '@nestjs/common';
import type { IAiProvider, AudioResult } from '../interfaces/ai-provider.interface';
import { AI_PROVIDER_TOKEN } from '../interfaces/ai-provider.interface';
import type { Redis } from 'ioredis';

// ── Types ──────────────────────────────────────────────────────────────────────

export interface SearchIntent {
  profession:          string | null;
  is_urgent:           boolean;
  problem_description: string;
  max_radius_km:       number | null;
  confidence:          number;
  transcribedText?:    string;
}

// ── Constants ──────────────────────────────────────────────────────────────────

const VALID_PROFESSIONS = new Set([
  'plumber', 'electrician', 'cleaner', 'painter', 'carpenter',
  'gardener', 'ac_repair', 'appliance_repair', 'mason', 'mechanic', 'mover',
]);

const FALLBACK: SearchIntent = {
  profession:          null,
  is_urgent:           false,
  problem_description: '',
  max_radius_km:       null,
  confidence:          0,
};

// ── System prompt with inline few-shot examples ───────────────────────────────
// These examples replace the Qdrant RAG step entirely.
// They are curated for Algerian Darija + Arabic + French + English.

const SYSTEM_PROMPT = `\
Tu es l'extracteur d'intention de Khidmeti, application algérienne de services à domicile.
Analyse la requête en Darija/Arabe/Français/Anglais ou tout mélange.
Réponds UNIQUEMENT en JSON brut — aucun markdown, aucun texte autour.

SCHÉMA EXACT:
{"profession":<string|null>,"is_urgent":<bool>,"problem_description":<string>,"max_radius_km":<number|null>,"confidence":<number>}

PROFESSIONS VALIDES (utilise exactement ces mots):
plumber | electrician | cleaner | painter | carpenter | gardener | ac_repair | appliance_repair | mason | mechanic | mover

RÈGLES:
- is_urgent: true SEULEMENT pour inondation / coupure totale / fuite gaz / serrure cassée la nuit
- problem_description: anglais, factuel, max 120 caractères
- confidence: 0.0 à 1.0
- Si tu n'es pas sûr de la profession → null

EXEMPLES (few-shot):

Requête: "عندي ماء ساقط من السقف"
{"profession":"plumber","is_urgent":false,"problem_description":"water leaking from ceiling","max_radius_km":null,"confidence":0.95}

Requête: "الضوء طاح في الدار كامل"
{"profession":"electrician","is_urgent":true,"problem_description":"total power outage in the house","max_radius_km":null,"confidence":0.98}

Requête: "الكليماتيزور ما يبردش وجاي الصيف"
{"profession":"ac_repair","is_urgent":false,"problem_description":"air conditioner not cooling, summer approaching","max_radius_km":null,"confidence":0.92}

Requête: "صنفارية مسدودة في الحمام"
{"profession":"plumber","is_urgent":false,"problem_description":"blocked drain in bathroom","max_radius_km":null,"confidence":0.94}

Requête: "الفريج خربان ما يبردش"
{"profession":"appliance_repair","is_urgent":false,"problem_description":"refrigerator not cooling","max_radius_km":null,"confidence":0.91}

Requête: "الباب ما يقفلش، القفل محطوب"
{"profession":"carpenter","is_urgent":true,"problem_description":"broken door lock, cannot secure home","max_radius_km":null,"confidence":0.96}

Requête: "j'ai une fuite d'eau sous l'évier"
{"profession":"plumber","is_urgent":false,"problem_description":"water leak under sink","max_radius_km":null,"confidence":0.97}

Requête: "prise électrique qui fait des étincelles"
{"profession":"electrician","is_urgent":true,"problem_description":"electrical outlet sparking","max_radius_km":null,"confidence":0.95}

Requête: "نبغي نصبغ الدار، قريب مني"
{"profession":"painter","is_urgent":false,"problem_description":"wants to paint house, looking for nearby worker","max_radius_km":5,"confidence":0.88}

Requête: "my toilet is overflowing"
{"profession":"plumber","is_urgent":true,"problem_description":"toilet overflowing","max_radius_km":null,"confidence":0.97}
`;

// ── Service ────────────────────────────────────────────────────────────────────

@Injectable()
export class IntentExtractorService {
  private readonly logger = new Logger(IntentExtractorService.name);

  // Simple LRU-like in-memory cache — no external dependency
  private readonly cache    = new Map<string, SearchIntent>();
  private readonly MAX_CACHE        = 50;
  private readonly RATE_LIMIT_MAX   = 20;
  private readonly RATE_LIMIT_WINDOW = 3_600_000; // 1h

  constructor(
    @Inject(AI_PROVIDER_TOKEN)
    private readonly ai: IAiProvider,
    @Optional() @Inject('REDIS_CLIENT')
    private readonly redis?: Redis,
  ) {}

  // ── Public API ──────────────────────────────────────────────────────────────

  async extractFromText(text: string, uid?: string): Promise<SearchIntent> {
    const trimmed = text.trim().slice(0, 2000);
    if (!trimmed) return { ...FALLBACK };

    if (uid) await this.checkRateLimit(uid);

    // Cache hit
    const key    = trimmed.toLowerCase();
    const cached = this.cache.get(key);
    if (cached) {
      this.logger.debug('Cache hit');
      return cached;
    }

    // Single Gemma4 call — reasoning handles multilingual intent extraction
    const raw    = await this.ai.generateText(trimmed, SYSTEM_PROMPT, { temperature: 0.05, maxTokens: 256 });
    const intent = this.parse(raw);
    this.setCache(key, intent);

    return intent;
  }

  async extractFromAudio(buffer: Buffer, mime: string, uid?: string): Promise<SearchIntent> {
    const { text, language }: AudioResult = await this.ai.processAudio(buffer, mime);
    if (!text.trim()) return { ...FALLBACK };

    this.logger.debug(`Audio transcribed [${language}]: ${text.slice(0, 80)}`);

    const intent = await this.extractFromText(text, uid);
    return { ...intent, transcribedText: text };
  }

  async extractFromImage(imageBase64: string, uid?: string): Promise<SearchIntent> {
    if (uid) await this.checkRateLimit(uid);

    const raw = await this.ai.analyzeImage(
      imageBase64,
      `Identifie le problème domestique visible dans cette image, puis extrait l'intention.\n${SYSTEM_PROMPT}`,
      { temperature: 0.05, maxTokens: 256 },
    );

    return this.parse(raw);
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  private parse(raw: string): SearchIntent {
    // Strip markdown fences and locate the JSON object
    const s = raw.replace(/```json|```/g, '').trim();
    // Skip any <|channel>thought...</channel|> thinking blocks (Gemma4 local)
    const cleaned = s.replace(/<\|channel>thought[\s\S]*?<channel\|>/g, '').trim();

    const i = cleaned.indexOf('{');
    const j = cleaned.lastIndexOf('}');
    if (i === -1 || j === -1) {
      this.logger.warn(`Could not find JSON in response: ${s.slice(0, 100)}`);
      return { ...FALLBACK };
    }

    try {
      const p = JSON.parse(cleaned.slice(i, j + 1)) as Partial<SearchIntent>;
      return {
        profession: (
          typeof p.profession === 'string' && VALID_PROFESSIONS.has(p.profession)
            ? p.profession
            : null
        ),
        is_urgent:           p.is_urgent === true,
        problem_description: (p.problem_description ?? '').slice(0, 120),
        max_radius_km:       typeof p.max_radius_km === 'number' ? p.max_radius_km : null,
        confidence:          typeof p.confidence    === 'number'
                               ? Math.min(1, Math.max(0, p.confidence))
                               : 0,
      };
    } catch (e) {
      this.logger.warn(`JSON parse failed: ${(e as Error).message}`);
      return { ...FALLBACK };
    }
  }

  private setCache(key: string, intent: SearchIntent): void {
    // Evict oldest entry when full (simple LRU)
    if (this.cache.size >= this.MAX_CACHE) {
      const oldest = this.cache.keys().next().value as string;
      this.cache.delete(oldest);
    }
    this.cache.set(key, intent);
  }

  private async checkRateLimit(uid: string): Promise<void> {
    if (!this.redis) return;
    const key = `ai_rate:${uid}`;
    const now  = Date.now();
    try {
      const pipeline = this.redis.pipeline();
      pipeline.zremrangebyscore(key, '-inf', now - this.RATE_LIMIT_WINDOW);
      pipeline.zcard(key);
      pipeline.zadd(key, now, `${now}`);
      pipeline.expire(key, 3600);
      const results = await pipeline.exec();
      const count   = (results?.[1]?.[1] as number) ?? 0;
      if (count >= this.RATE_LIMIT_MAX) {
        await this.redis.zrem(key, `${now}`);
        const { AiRateLimitException } = await import('../exceptions/ai-provider.exception');
        throw new AiRateLimitException();
      }
    } catch (e) {
      // Re-throw rate limit errors; silently degrade on Redis errors
      const msg = (e as Error).constructor?.name;
      if (msg === 'AiRateLimitException') throw e;
      this.logger.warn(`Redis rate-limit degraded: ${(e as Error).message}`);
    }
  }
}
