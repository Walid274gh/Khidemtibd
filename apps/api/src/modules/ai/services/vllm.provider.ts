import { Injectable, Logger } from '@nestjs/common';
import axios from 'axios';
import { AiProvider, AiTextOptions, AudioResult } from '../ai-provider.abstract';

interface VllmMessage {
  role: string;
  content: unknown[];
}

interface VllmResponse {
  choices: Array<{ message: { content: string } }>;
}

@Injectable()
export class VllmProvider extends AiProvider {
  private readonly logger = new Logger(VllmProvider.name);
  private readonly baseUrl: string;
  private readonly model = 'google/gemma-4-E4B-it';
  private readonly ollamaEmbedUrl: string;

  constructor() {
    super();
    this.baseUrl = process.env['VLLM_BASE_URL'] ?? 'http://vllm:8000';
    // Embeddings via separate Ollama container in GPU stack
    this.ollamaEmbedUrl = process.env['OLLAMA_BASE_URL'] ?? 'http://ollama-embed:11434';
  }

  async generateText(
    prompt: string,
    systemPrompt: string,
    options: AiTextOptions = {},
  ): Promise<string> {
    try {
      const response = await axios.post<VllmResponse>(
        `${this.baseUrl}/v1/chat/completions`,
        {
          model: this.model,
          temperature: options.temperature ?? 0.05,
          max_tokens: options.maxTokens ?? 300,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: prompt },
          ],
        },
        { timeout: 15000 },
      );
      return response.data.choices[0]?.message.content ?? '';
    } catch (err) {
      this.logger.error('VllmProvider.generateText failed', err);
      throw err;
    }
  }

  async analyzeImage(
    imageBase64: string,
    prompt: string,
    options: AiTextOptions = {},
  ): Promise<string> {
    try {
      // vLLM OpenAI-compatible multimodal: image BEFORE text
      const userContent: VllmMessage['content'] = [
        { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } },
        { type: 'text', text: prompt },
      ];
      const response = await axios.post<VllmResponse>(
        `${this.baseUrl}/v1/chat/completions`,
        {
          model: this.model,
          temperature: options.temperature ?? 0.05,
          max_tokens: options.maxTokens ?? 300,
          messages: [{ role: 'user', content: userContent }],
        },
        { timeout: 15000 },
      );
      return response.data.choices[0]?.message.content ?? '';
    } catch (err) {
      this.logger.error('VllmProvider.analyzeImage failed', err);
      throw err;
    }
  }

  async processAudio(
    audioBuffer: Buffer,
    mime: string,
    options: AiTextOptions = {},
  ): Promise<AudioResult> {
    try {
      // vLLM native audio via --limit-mm-per-prompt audio=1
      const audioBase64 = audioBuffer.toString('base64');
      const userContent: VllmMessage['content'] = [
        { type: 'input_audio', input_audio: { data: audioBase64, format: mime.split('/')[1] ?? 'm4a' } },
        { type: 'text', text: 'Transcribe this audio and return JSON: {"text": "<transcription>", "language": "<lang_code>"}' },
      ];
      const response = await axios.post<VllmResponse>(
        `${this.baseUrl}/v1/chat/completions`,
        {
          model: this.model,
          temperature: options.temperature ?? 0.05,
          max_tokens: options.maxTokens ?? 500,
          messages: [{ role: 'user', content: userContent }],
        },
        { timeout: 30000 },
      );
      const raw = (response.data.choices[0]?.message.content ?? '').trim();
      try {
        const parsed = JSON.parse(raw) as { text: string; language: string };
        return parsed;
      } catch {
        return { text: raw, language: 'auto' };
      }
    } catch (err) {
      this.logger.error('VllmProvider.processAudio failed', err);
      throw err;
    }
  }

  async generateEmbedding(text: string): Promise<number[]> {
    try {
      const response = await axios.post<{ embedding: number[] }>(
        `${this.ollamaEmbedUrl}/api/embeddings`,
        { model: 'nomic-embed-text', prompt: text },
        { timeout: 10000 },
      );
      return response.data.embedding;
    } catch (err) {
      this.logger.error('VllmProvider.generateEmbedding failed', err);
      throw err;
    }
  }
}
