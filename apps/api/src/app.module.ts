import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { ThrottlerModule } from '@nestjs/throttler';
import { DatabaseModule } from './database/database.module';
import { QdrantModule } from './qdrant/qdrant.module';
import { FirebaseConfigModule } from './config/firebase.config';
import { AiModule } from './modules/ai/ai.module';
import { MediaModule } from './modules/media/media.module';

@Module({
  imports: [
    // ── Config (env vars) ──────────────────────────────────────────────────
    ConfigModule.forRoot({
      isGlobal:    true,
      envFilePath: '../../.env',
    }),

    // ── Firebase Admin (verifies ID tokens in FirebaseAuthGuard) ───────────
    FirebaseConfigModule,

    // ── MongoDB ────────────────────────────────────────────────────────────
    MongooseModule.forRootAsync({
      imports:    [ConfigModule],
      inject:     [ConfigService],
      useFactory: (config: ConfigService) => ({
        uri:                       config.getOrThrow<string>('MONGODB_URI'),
        maxPoolSize:               10,
        serverSelectionTimeoutMS:  5000,
        socketTimeoutMS:           45000,
      }),
    }),

    // ── Rate limiting ──────────────────────────────────────────────────────
    ThrottlerModule.forRoot([
      { name: 'short',  ttl: 1_000,  limit: 20  },
      { name: 'medium', ttl: 10_000, limit: 100 },
      { name: 'long',   ttl: 60_000, limit: 300 },
    ]),

    // ── Domain modules ─────────────────────────────────────────────────────
    DatabaseModule,
    QdrantModule,
    AiModule,
    MediaModule,
  ],
})
export class AppModule {}
