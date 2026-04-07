import { Module } from '@nestjs/common';
import { AiProvider } from './interfaces/ai-provider.interface';
import { createAiProvider } from './factories/ai-provider.factory';
import { QdrantService } from './services/qdrant.service';
import { QdrantInitService } from './services/qdrant-init.service';
import { IntentExtractorService } from './services/intent-extractor.service';
import { WhisperService } from './services/whisper.service';
import { AiController } from './ai.controller';
import { AuthModule } from '../auth/auth.module';
import Redis from 'ioredis';

@Module({
  imports: [AuthModule],
  controllers: [AiController],
  providers: [
    // ── AI provider (Strategy Pattern) ──────────────────────────────────────
    {
      provide:    AiProvider,
      useFactory: createAiProvider,
    },

    // ── Redis client for rate limiting ───────────────────────────────────────
    // Optional — if Redis is unreachable the rate limiter degrades gracefully.
    {
      provide:    'REDIS_CLIENT',
      useFactory: (): Redis | null => {
        const url = process.env['REDIS_URL'];
        if (!url) return null;
        const client = new Redis(url, {
          lazyConnect: true,
          maxRetriesPerRequest: 1,
          enableOfflineQueue: false,
        });
        client.on('error', (err: Error) => {
          // Suppress connection errors — rate limiter degrades gracefully
          void err;
        });
        return client;
      },
    },

    // ── Core AI services ─────────────────────────────────────────────────────
    QdrantService,
    QdrantInitService,
    WhisperService,
    IntentExtractorService,
  ],
  exports: [AiProvider, IntentExtractorService, QdrantService, WhisperService],
})
export class AiModule {}
