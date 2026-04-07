import { Injectable, Module } from '@nestjs/common';
import { MongooseOptionsFactory, MongooseModuleOptions } from '@nestjs/mongoose';

@Injectable()
export class DatabaseConfigService implements MongooseOptionsFactory {
  createMongooseOptions(): MongooseModuleOptions {
    const uri = process.env['MONGODB_URI'];
    if (!uri) throw new Error('MONGODB_URI is not defined');

    return {
      uri,
      retryAttempts: 5,
      retryDelay: 3000,
      connectionFactory: (connection: unknown) => {
        console.log('✅ MongoDB connected');
        return connection;
      },
    };
  }
}

@Module({ providers: [DatabaseConfigService], exports: [DatabaseConfigService] })
export class DatabaseConfigModule {}
