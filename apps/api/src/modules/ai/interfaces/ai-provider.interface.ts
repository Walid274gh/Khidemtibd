// ══════════════════════════════════════════════════════════════════════════════
// IAiProvider — Strategy interface
//
// DESIGN INTENT:
//   Every AI backend (Gemini API, Ollama local, vLLM GPU) implements this
//   single interface.  The rest of the codebase depends ONLY on this contract.
//   Switching from cloud to 100% local is one env-var change: AI_PROVIDER=ollama
// ══════════════════════════════════════════════════════════════════════════════

export interface AudioResult {
  text:     string;
  language: string;
}

export interface IAiProvider {
  /** Generate text from a prompt + system instruction */
  generateText(
    prompt:       string,
    systemPrompt: string,
    opts?: { temperature?: number; maxTokens?: number },
  ): Promise<string>;

  /** Analyze a base64-encoded image and return text */
  analyzeImage(
    imageBase64: string,
    prompt:      string,
    opts?: { temperature?: number; maxTokens?: number },
  ): Promise<string>;

  /** Transcribe audio buffer and return text + detected language */
  processAudio(
    audioBuffer: Buffer,
    mime:        string,
    opts?: { temperature?: number; maxTokens?: number },
  ): Promise<AudioResult>;
}

export const AI_PROVIDER_TOKEN = 'AI_PROVIDER';
