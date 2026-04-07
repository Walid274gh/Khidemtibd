import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { QdrantClient } from '@qdrant/js-client-rest';

export const COLLECTION_WORKERS = 'workers_vectors';
export const COLLECTION_REQUESTS = 'service_requests_vectors';
export const VECTOR_SIZE = 768; // nomic-embed-text dimension

@Injectable()
export class QdrantInitService implements OnModuleInit {
  private readonly logger = new Logger(QdrantInitService.name);
  private readonly client: QdrantClient;

  constructor(private readonly config: ConfigService) {
    this.client = new QdrantClient({
      url: this.config.getOrThrow<string>('QDRANT_URL'),
    });
  }

  get qdrantClient(): QdrantClient {
    return this.client;
  }

  async onModuleInit(): Promise<void> {
    await this.ensureCollection(COLLECTION_WORKERS);
    await this.ensureCollection(COLLECTION_REQUESTS);
  }

  private async ensureCollection(name: string): Promise<void> {
    try {
      const existing = await this.client.getCollections();
      const found = existing.collections.some((c) => c.name === name);

      if (!found) {
        await this.client.createCollection(name, {
          vectors: {
            size: VECTOR_SIZE,
            distance: 'Cosine',
          },
          optimizers_config: { default_segment_number: 2 },
          replication_factor: 1,
        });
        this.logger.log(`Qdrant collection created: ${name}`);
      } else {
        this.logger.log(`Qdrant collection already exists: ${name}`);
      }
    } catch (err: unknown) {
      this.logger.error(`Failed to ensure Qdrant collection ${name}`, err);
      throw err;
    }
  }

  async upsertWorkerVector(
    workerId: string,
    vector: number[],
    payload: Record<string, unknown>,
  ): Promise<void> {
    await this.client.upsert(COLLECTION_WORKERS, {
      wait: true,
      points: [{ id: workerId, vector, payload }],
    });
  }

  async upsertRequestVector(
    requestId: string,
    vector: number[],
    payload: Record<string, unknown>,
  ): Promise<void> {
    await this.client.upsert(COLLECTION_REQUESTS, {
      wait: true,
      points: [{ id: requestId, vector, payload }],
    });
  }

  async searchWorkers(
    vector: number[],
    filter: Record<string, unknown>,
    limit = 20,
  ) {
    return this.client.search(COLLECTION_WORKERS, {
      vector,
      filter,
      limit,
      with_payload: true,
    });
  }

  async searchRequests(
    vector: number[],
    filter: Record<string, unknown>,
    limit = 20,
  ) {
    return this.client.search(COLLECTION_REQUESTS, {
      vector,
      filter,
      limit,
      with_payload: true,
    });
  }

  async deleteWorkerVector(workerId: string): Promise<void> {
    await this.client.delete(COLLECTION_WORKERS, {
      wait: true,
      points: [workerId],
    });
  }

  async deleteRequestVector(requestId: string): Promise<void> {
    await this.client.delete(COLLECTION_REQUESTS, {
      wait: true,
      points: [requestId],
    });
  }
}
