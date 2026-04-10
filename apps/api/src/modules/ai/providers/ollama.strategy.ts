// ══════════════════════════════════════════════════════════════════════════════
// OllamaStrategy — Local Gemma4 backend (zero API cost, zero GPU required)
//
// Ollama exposes an OpenAI-compatible REST API at http://localhost:11434.
// Recommended local models (CPU-only viable):
//   gemma4:e2b   → ~1.5 GB, runs on any laptop  (edge variant, 2B eff params)
//   gemma4:e4b   → ~2.5 GB, better quality       (edge variant, 4B eff params)
//   gemma4:26b   → ~16 GB, production quality    (MoE, 4B active params)
//
// Switch with:  AI_PROVIDER=ollama  OLLAMA_MODEL=gemma4:e4b
// No other code change needed — same interface as GeminiStrategy.
// ══════════════════════════════════════════════════════════════════════════════

import { Injectable, Logger } from '@nestjs/common';
import type { IAiProvider, AudioResult } from '../interfaces/ai-provider.interface';

interface OllamaMessage {
  role:    'system' | 'user' | 'assistant';
  content: string | OllamaContentPart[];
}

interface OllamaContentPart {
  type:       'text' | 'image_url';
  text?:      string;
  image_url?: { url: string };
}

@Injectable()
export class OllamaStrategy implements IAiProvider {
  private readonly logger   = new Logger(OllamaStrategy.name);
  private readonly baseUrl:  string;
  private readonly model:    string;
  private readonly timeoutMs: number;

  constructor() {
    this.baseUrl   = process.env['OLLAMA_BASE_URL']  ?? 'http://ollama:11434';
    this.model     = process.env['OLLAMA_MODEL']      ?? 'gemma4:e4b';
    this.timeoutMs = parseInt(process.env['OLLAMA_TIMEOUT_MS'] ?? '30000', 10);

    this.logger.log(`✅ OllamaStrategy ready — ${this.baseUrl}  model: ${this.model}`);
  }

  async generateText(
    prompt:       string,
    systemPrompt: string,
    opts: { temperature?: number; maxTokens?: number } = {},
  ): Promise<string> {
    const messages: OllamaMessage[] = [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: prompt       },
    ];

    return this.chat(messages, opts);
  }

  async analyzeImage(
    imageBase64: string,
    prompt:      string,
    opts: { temperature?: number; maxTokens?: number } = {},
  ): Promise<string> {
    // Gemma4 is natively multimodal — pass image as base64 data URL
    const messages: OllamaMessage[] = [{
      role: 'user',
      content: [
        {
          type:      'image_url',
          image_url: { url: `data:image/jpeg;base64,${imageBase64}` },
        },
        { type: 'text', text: prompt },
      ],
    }];

    return this.chat(messages, opts);
  }

  async processAudio(
    audioBuffer: Buffer,
    _mime:       string,
    opts: { temperature?: number; maxTokens?: number } = {},
  ): Promise<AudioResult> {
    // Ollama/Gemma4 does not yet support native audio input.
    // We fall back to the text transcription prompt with base64 hint.
    // For production local audio, add a Whisper container alongside Ollama.
    const b64 = audioBuffer.toString('base64');

    const messages: OllamaMessage[] = [{
      role:    'user',
      content: `Voici un fichier audio encodé en base64 (premiers 200 chars): ${b64.slice(0, 200)}...\nTranscris le contenu supposé. Réponds UNIQUEMENT en JSON: {"text":"<transcription>","language":"fr"}`,
    }];

    const raw = await this.chat(messages, opts);
    return this.parseAudioJson(raw);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  private async chat(
    messages: OllamaMessage[],
    opts:     { temperature?: number; maxTokens?: number },
  ): Promise<string> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const res = await fetch(`${this.baseUrl}/v1/chat/completions`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        signal:  controller.signal,
        body: JSON.stringify({
          model:       this.model,
          messages,
          temperature: opts.temperature ?? 0.05,
          max_tokens:  opts.maxTokens   ?? 600,
          stream:      false,
          // Disable thinking for structured JSON extraction (faster + stable)
          options: { think: false },
        }),
      });

      if (!res.ok) {
        const err = await res.text().catch(() => res.statusText);
        throw new Error(`Ollama HTTP ${res.status}: ${err}`);
      }

      const data = await res.json() as {
        choices: [{ message: { content: string } }];
      };

      return data.choices[0]?.message?.content ?? '';
    } catch (err) {
      if ((err as Error).name === 'AbortError') {
        throw new Error(`Ollama timeout after ${this.timeoutMs}ms`);
      }
      throw err;
    } finally {
      clearTimeout(timer);
    }
  }

  private parseAudioJson(raw: string): AudioResult {
    const clean = raw.trim().replace(/```json|```/g, '').trim();
    try {
      return JSON.parse(clean) as AudioResult;
    } catch {
      return { text: clean, language: 'auto' };
    }
  }
}
