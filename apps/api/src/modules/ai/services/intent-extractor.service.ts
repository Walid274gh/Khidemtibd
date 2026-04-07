import { Injectable, Logger } from '@nestjs/common';
import { AiProvider } from '../ai-provider.abstract';
import { QdrantService } from './qdrant.service';

export interface SearchIntent {
  profession: string | null;
  is_urgent: boolean;
  problem_description: string;
  max_radius_km: number | null;
  confidence: number;
  transcribedText?: string;
}

const VALID_PROFESSIONS = new Set([
  'plumber', 'electrician', 'cleaner', 'painter', 'carpenter',
  'gardener', 'ac_repair', 'appliance_repair', 'mason', 'mechanic', 'mover',
]);

const SYSTEM_PROMPT = `You are an intent extractor for Khidmeti, an Algerian home services app.
Your ONLY job is to analyze the user's home problem description (which may be
in French, Arabic, Algerian Darija, or English, or any mix) and return a JSON object.

CRITICAL: Respond with ONLY raw JSON. No markdown, no code fences, no explanations.

JSON schema (required, exact structure):
{
  "profession": "<string | null>",
  "is_urgent": <boolean>,
  "problem_description": "<string>",
  "max_radius_km": <number | null>,
  "confidence": <number>
}

Valid profession values — use EXACTLY one of these strings or null:
plumber, electrician, cleaner, painter, carpenter, gardener,
ac_repair, appliance_repair, mason, mechanic, mover

Rules:
- profession: the single most appropriate trade. null if unclear.
- is_urgent: true ONLY for genuine emergencies — flooding, complete power outage, gas leak, fire risk, broken lock at night. Default false.
- problem_description: concise factual English description, max 120 characters.
- max_radius_km: null unless user explicitly requests a distance.
- confidence: 0.0 to 1.0.`;

@Injectable()
export class IntentExtractorService {
  private readonly logger = new Logger(IntentExtractorService.name);
  private readonly cache = new Map<string, SearchIntent>();
  private readonly MAX_CACHE = 20;

  constructor(
    private readonly aiProvider: AiProvider,
    private readonly qdrant: QdrantService,
  ) {}

  async extractFromText(text: string): Promise<SearchIntent> {
    const key = text.trim().toLowerCase().slice(0, 200);

    const cached = this.cache.get(key);
    if (cached) return cached;

    try {
      const embedding = await this.aiProvider.generateEmbedding(text.trim().slice(0, 2000));
      const candidates = await this.qdrant.search('service_descriptions', embedding, 5);

      const context = candidates.length > 0
        ? 'Relevant examples:\n' +
          candidates
            .map((c) => c.payload['exampleText'] as string | undefined ?? '')
            .filter(Boolean)
            .join('\n')
        : '';

      const augmented = context ? `${context}\n\nUser query: ${text}` : text;
      const raw = await this.aiProvider.generateText(augmented, SYSTEM_PROMPT, {
        temperature: 0.05,
        maxTokens: 300,
      });

      const intent = this.parseIntent(raw);

      // LRU eviction
      if (this.cache.size >= this.MAX_CACHE) {
        const first = this.cache.keys().next().value as string;
        this.cache.delete(first);
      }
      this.cache.set(key, intent);
      return intent;
    } catch (err) {
      this.logger.error('IntentExtractorService.extractFromText failed', err);
      throw err;
    }
  }

  async extractFromAudio(audioBuffer: Buffer, mime: string): Promise<SearchIntent> {
    try {
      const { text, language } = await this.aiProvider.processAudio(audioBuffer, mime);
      if (!text.trim()) {
        return { profession: null, is_urgent: false, problem_description: '', max_radius_km: null, confidence: 0.0 };
      }
      this.logger.debug(`Audio transcribed [${language}]: ${text}`);
      const intent = await this.extractFromText(text);
      return { ...intent, transcribedText: text };
    } catch (err) {
      this.logger.error('IntentExtractorService.extractFromAudio failed', err);
      throw err;
    }
  }

  async extractFromImage(imageBase64: string): Promise<SearchIntent> {
    try {
      const raw = await this.aiProvider.analyzeImage(
        imageBase64,
        'Analyze this image to identify the home maintenance problem. ' + SYSTEM_PROMPT,
        { temperature: 0.05, maxTokens: 300 },
      );
      return this.parseIntent(raw);
    } catch (err) {
      this.logger.error('IntentExtractorService.extractFromImage failed', err);
      throw err;
    }
  }

  private parseIntent(raw: string): SearchIntent {
    let s = raw.replace(/```json|```/g, '').trim();
    const start = s.indexOf('{');
    const end = s.lastIndexOf('}');
    if (start === -1 || end === -1) {
      return { profession: null, is_urgent: false, problem_description: '', max_radius_km: null, confidence: 0.0 };
    }
    s = s.slice(start, end + 1);
    try {
      const parsed = JSON.parse(s) as Partial<SearchIntent>;
      const profession = typeof parsed.profession === 'string' && VALID_PROFESSIONS.has(parsed.profession)
        ? parsed.profession
        : null;
      return {
        profession,
        is_urgent: parsed.is_urgent === true,
        problem_description: (parsed.problem_description ?? '').slice(0, 120),
        max_radius_km: typeof parsed.max_radius_km === 'number' ? parsed.max_radius_km : null,
        confidence: typeof parsed.confidence === 'number' ? Math.min(1, Math.max(0, parsed.confidence)) : 0.0,
      };
    } catch {
      return { profession: null, is_urgent: false, problem_description: '', max_radius_km: null, confidence: 0.0 };
    }
  }
}
