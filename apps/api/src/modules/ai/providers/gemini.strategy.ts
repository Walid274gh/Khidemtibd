// ══════════════════════════════════════════════════════════════════════════════
// GeminiStrategy — Google AI API backend
//
// Uses @google/genai v1.x with gemma-4-31b-it (or any GEMMA4_MODEL).
// Zero external embedding model — Gemma4's built-in reasoning handles
// multilingual intent extraction natively.
// ══════════════════════════════════════════════════════════════════════════════

import { Injectable, Logger } from '@nestjs/common';
import { GoogleGenAI } from '@google/genai';
import type { Content, Part, GenerateContentConfig } from '@google/genai';
import type { IAiProvider, AudioResult } from '../interfaces/ai-provider.interface';

@Injectable()
export class GeminiStrategy implements IAiProvider {
  private readonly logger = new Logger(GeminiStrategy.name);
  private readonly ai: GoogleGenAI;
  private readonly MODEL: string;

  constructor() {
    const apiKey = process.env['GEMINI_API_KEY'];
    if (!apiKey) throw new Error('GEMINI_API_KEY is missing');

    this.MODEL = process.env['GEMMA4_MODEL'] ?? 'gemma-4-31b-it';
    this.ai    = new GoogleGenAI({ apiKey });

    this.logger.log(`✅ GeminiStrategy ready — model: ${this.MODEL}`);
  }

  async generateText(
    prompt:       string,
    systemPrompt: string,
    opts: { temperature?: number; maxTokens?: number } = {},
  ): Promise<string> {
    const config: GenerateContentConfig = {
      systemInstruction: systemPrompt,
      temperature:       opts.temperature ?? 0.05,
      maxOutputTokens:   opts.maxTokens   ?? 600,
    };

    const response = await this.ai.models.generateContent({
      model:    this.MODEL,
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      config,
    });

    return response.text ?? '';
  }

  async analyzeImage(
    imageBase64: string,
    prompt:      string,
    opts: { temperature?: number; maxTokens?: number } = {},
  ): Promise<string> {
    const contents: Content[] = [{
      role:  'user',
      parts: [
        { inlineData: { data: imageBase64, mimeType: 'image/jpeg' } } as Part,
        { text: prompt },
      ],
    }];

    const response = await this.ai.models.generateContent({
      model:    this.MODEL,
      contents,
      config: {
        temperature:     opts.temperature ?? 0.05,
        maxOutputTokens: opts.maxTokens   ?? 600,
      },
    });

    return response.text ?? '';
  }

  async processAudio(
    audioBuffer: Buffer,
    mime:        string,
    opts: { temperature?: number; maxTokens?: number } = {},
  ): Promise<AudioResult> {
    const contents: Content[] = [{
      role:  'user',
      parts: [
        { inlineData: { data: audioBuffer.toString('base64'), mimeType: mime } } as Part,
        {
          text: 'Transcris cet audio. Réponds UNIQUEMENT en JSON brut sans markdown:\n{"text":"<transcription>","language":"<code_langue>"}',
        },
      ],
    }];

    const response = await this.ai.models.generateContent({
      model:    this.MODEL,
      contents,
      config: {
        temperature:     opts.temperature ?? 0.05,
        maxOutputTokens: opts.maxTokens   ?? 500,
      },
    });

    return this.parseAudioJson(response.text ?? '');
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
