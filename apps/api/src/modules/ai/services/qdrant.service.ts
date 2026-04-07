import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { QdrantClient } from '@qdrant/js-client-rest';

export interface QdrantSearchResult {
  id: string | number;
  score: number;
  payload: Record<string, unknown>;
}

@Injectable()
export class QdrantService implements OnModuleInit {
  private readonly logger = new Logger(QdrantService.name);
  private client!: QdrantClient;

  onModuleInit(): void {
    const url = process.env['QDRANT_URL'] ?? 'http://qdrant:6333';
    const apiKey = process.env['QDRANT_API_KEY'];
    this.client = new QdrantClient({ url, apiKey: apiKey || undefined });
    this.logger.log(`Qdrant client initialized → ${url}`);
  }

  async search(
    collectionName: string,
    vector: number[],
    limit = 5,
    filter?: Record<string, unknown>,
  ): Promise<QdrantSearchResult[]> {
    try {
      const results = await this.client.search(collectionName, {
        vector,
        limit,
        filter: filter as Parameters<QdrantClient['search']>[1]['filter'],
        with_payload: true,
      });
      return results.map((r) => ({
        id: r.id,
        score: r.score,
        payload: (r.payload ?? {}) as Record<string, unknown>,
      }));
    } catch (err) {
      this.logger.error(`QdrantService.search [${collectionName}] failed`, err);
      throw err;
    }
  }

  async upsert(
    collectionName: string,
    id: string,
    vector: number[],
    payload: Record<string, unknown>,
  ): Promise<void> {
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
}
