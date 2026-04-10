import { Module } from '@nestjs/common';
import { Gemma4Provider } from './providers/gemma4.provider';
import { QdrantService } from './services/qdrant.service';
import { QdrantInitService } from './services/qdrant-init.service';
import { IntentExtractorService } from './services/intent-extractor.service';
import { AiController } from './ai.controller';
import { AuthModule } from '../auth/auth.module';
import Redis from 'ioredis';

@Module({
  imports:     [AuthModule],
  controllers: [AiController],
  providers: [
    Gemma4Provider,

    {
      provide:    'REDIS_CLIENT',
      useFactory: (): Redis | null => {
        const url = process.env['REDIS_URL'];
        if (!url) return null;
        const client = new Redis(url, {
          lazyConnect:          true,
          maxRetriesPerRequest: 1,
          enableOfflineQueue:   false,
        });
        client.on('error', () => { /* dégradation silencieuse */ });
        return client;
      },
    },

    QdrantService,
    QdrantInitService,
    IntentExtractorService,
  ],
  exports: [Gemma4Provider, IntentExtractorService, QdrantService],
})
export class AiModule {}
