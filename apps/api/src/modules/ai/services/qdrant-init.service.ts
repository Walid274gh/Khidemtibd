import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { QdrantService } from './qdrant.service';

@Injectable()
export class QdrantInitService implements OnModuleInit {
  private readonly logger = new Logger(QdrantInitService.name);

  // text-embedding-004 (Gemini) and nomic-embed-text (Ollama) are both 768-dim
  private readonly VECTOR_SIZE = 768;

  constructor(private readonly qdrant: QdrantService) {}

  /**
   * Ensures collections exist with a retry guard.
   * Safe to call multiple times — createCollection is idempotent.
   * Non-fatal: if Qdrant is still unreachable, the QdrantService.ready
   * flag stays false and all searches degrade gracefully to LLM-only.
   */
  async onModuleInit(): Promise<void> {
    await this.ensureCollection('service_descriptions');
    await this.ensureCollection('worker_profiles');
  }

  private async ensureCollection(name: string): Promise<void> {
    try {
      const exists = await this.qdrant.collectionExists(name);
      if (!exists) {
        await this.qdrant.createCollection(name, this.VECTOR_SIZE);
        this.logger.log(`✅ Qdrant collection ready: ${name}`);
      } else {
        this.logger.debug(`Qdrant collection already exists: ${name}`);
      }
    } catch (err) {
      this.logger.warn(
        `QdrantInitService: could not ensure collection "${name}" — ` +
        `will retry on next restart. RAG examples unavailable until then. ` +
        `Error: ${(err as Error).message}`,
      );
      // Non-fatal — app continues without RAG examples
    }
  }
}
