import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';

@Module({ imports: [ConfigModule] })
export class AppConfigModule {}

export { ConfigService };
