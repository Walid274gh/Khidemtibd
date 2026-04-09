import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { QdrantClient } from '@qdrant/js-client-rest';

export interface QdrantSearchResult {
  id:      string | number;
  score:   number;
  payload: Record<string, unknown>;
}

/** Exponential backoff config */
const RETRY_ATTEMPTS = 8;
const RETRY_BASE_MS  = 500;

@Injectable()
export class QdrantService implements OnModuleInit {
  private readonly logger = new Logger(QdrantService.name);
  private client!: QdrantClient;
  private ready = false;

  onModuleInit(): void {
    const url    = process.env['QDRANT_URL'] ?? 'http://qdrant:6333';
    const apiKey = process.env['QDRANT_API_KEY'];
    this.client  = new QdrantClient({ url, apiKey: apiKey || undefined });
    this.logger.log(`Qdrant client initialized → ${url}`);

    // Probe connection asynchronously — don't block NestJS bootstrap
    void this.probeConnection();
  }

  // ── Public API ─────────────────────────────────────────────────────────

  async search(
    collectionName: string,
    vector:         number[],
    limit           = 5,
    filter?:        Record<string, unknown>,
  ): Promise<QdrantSearchResult[]> {
    if (!this.ready) {
      // Graceful degradation: skip RAG when Qdrant is unavailable
      this.logger.warn(`QdrantService.search skipped — Qdrant not ready`);
      return [];
    }

    try {
      const results = await this.client.search(collectionName, {
        vector,
        limit,
        filter:       filter as Parameters<QdrantClient['search']>[1]['filter'],
        with_payload: true,
      });
      return results.map((r) => ({
        id:      r.id,
        score:   r.score,
        payload: (r.payload ?? {}) as Record<string, unknown>,
      }));
    } catch (err) {
      this.logger.error(`QdrantService.search [${collectionName}] failed`, err);
      // Return empty — intent extraction falls back to LLM-only (no RAG)
      return [];
    }
  }

  async upsert(
    collectionName: string,
    id:             string,
    vector:         number[],
    payload:        Record<string, unknown>,
  ): Promise<void> {
    if (!this.ready) {
      this.logger.warn(`QdrantService.upsert skipped — Qdrant not ready`);
      return;
    }

    try {
      await this.client.upsert(collectionName, {
        points: [{ id, vector, payload }],
      });
    } catch (err) {
      this.logger.error(`QdrantService.upsert [${collectionName}] failed`, err);
      throw err;
    }
  }

  async collectionExists(name: string): Promise<boolean> {
    try {
      const info = await this.client.getCollection(name);
      return !!info;
    } catch {
      return false;
    }
  }

  async createCollection(name: string, vectorSize: number): Promise<void> {
    try {
      await this.client.createCollection(name, {
        vectors: { size: vectorSize, distance: 'Cosine' },
      });
      this.logger.log(`Qdrant collection created: ${name}`);
    } catch (err) {
      this.logger.error(`QdrantService.createCollection [${name}] failed`, err);
      throw err;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /**
   * Probes the Qdrant connection with exponential backoff.
   * Sets `this.ready = true` on success so search() can proceed.
   * Called fire-and-forget from onModuleInit — never crashes the app.
   */
  private async probeConnection(): Promise<void> {
    for (let attempt = 1; attempt <= RETRY_ATTEMPTS; attempt++) {
      try {
        await this.client.getCollections();
        this.ready = true;
        this.logger.log('✅ QdrantService connection confirmed — RAG enabled');
        return;
      } catch (err) {
        const delay = Math.min(RETRY_BASE_MS * 2 ** (attempt - 1), 30_000);
        this.logger.warn(
          `QdrantService probe failed (${attempt}/${RETRY_ATTEMPTS}), ` +
          `retry in ${delay}ms — ${(err as Error).message}`,
        );
        await this.sleep(delay);
      }
    }
    this.logger.error(
      'QdrantService: all probes failed. RAG disabled — intent extraction runs LLM-only.',
    );
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
