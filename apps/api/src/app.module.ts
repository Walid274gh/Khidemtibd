import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { RedisModule } from '@nestjs-modules/ioredis';
import Joi from 'joi';
import { AppConfigModule } from './config/app.config';
import { DatabaseConfigModule, DatabaseConfigService } from './config/database.config';
import { FirebaseConfigModule } from './config/firebase.config';
import { AuthModule } from './modules/auth/auth.module';
import { UsersModule } from './modules/users/users.module';
import { WorkersModule } from './modules/workers/workers.module';
import { ServiceRequestsModule } from './modules/service-requests/service-requests.module';
import { BidsModule } from './modules/bids/bids.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { LocationModule } from './modules/location/location.module';
import { AiModule } from './modules/ai/ai.module';
import { MediaModule } from './modules/media/media.module';

@Module({
  imports: [
    // Config with validation — crashes on startup if required vars missing
    ConfigModule.forRoot({
      isGlobal: true,
      validationSchema: Joi.object({
        NODE_ENV: Joi.string().valid('development', 'production', 'test').default('development'),
        PORT: Joi.number().default(3000),
        MONGODB_URI: Joi.string().required(),
        REDIS_URL: Joi.string().required(),
        REDIS_PASSWORD: Joi.string().required(),
        FIREBASE_PROJECT_ID: Joi.string().required(),
        FIREBASE_CLIENT_EMAIL: Joi.string().required(),
        FIREBASE_PRIVATE_KEY: Joi.string().required(),
        AI_PROVIDER: Joi.string().valid('gemini', 'ollama', 'vllm').default('gemini'),
        MINIO_ENDPOINT: Joi.string().required(),
        MINIO_ACCESS_KEY: Joi.string().required(),
        MINIO_SECRET_KEY: Joi.string().required(),
        QDRANT_URL: Joi.string().required(),
      }),
    }),

    // MongoDB
    MongooseModule.forRootAsync({
      useClass: DatabaseConfigService,
    }),

    // Redis
    RedisModule.forRootAsync({
      useFactory: () => ({
        type: 'single',
        url: process.env['REDIS_URL'] ?? '',
        options: { password: process.env['REDIS_PASSWORD'] },
      }),
    }),

    AppConfigModule,
    DatabaseConfigModule,
    FirebaseConfigModule,
    AuthModule,
    UsersModule,
    WorkersModule,
    ServiceRequestsModule,
    BidsModule,
    NotificationsModule,
    LocationModule,
    AiModule,
    MediaModule,
  ],
})
export class AppModule {}
