import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { QdrantService } from './qdrant.service';

@Injectable()
export class QdrantInitService implements OnModuleInit {
  private readonly logger = new Logger(QdrantInitService.name);

  // nomic-embed-text embedding dimension
  private readonly VECTOR_SIZE = 768;

  constructor(private readonly qdrant: QdrantService) {}

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
      this.logger.error(`Failed to ensure collection ${name}`, err);
      // Non-fatal: app still boots — collection will be retried on next start
    }
  }
}
