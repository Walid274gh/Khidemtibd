import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as Minio from 'minio';
import { randomUUID } from 'crypto';
import { MinioConfigService } from '../../config/minio.config';

export interface UploadResult {
  url: string;
  key: string;
}

@Injectable()
export class MediaService implements OnModuleInit {
  private readonly logger = new Logger(MediaService.name);
  private client!: Minio.Client;

  constructor(private readonly config: MinioConfigService) {}

  onModuleInit(): void {
    this.client = new Minio.Client({
      endPoint: this.config.endpoint,
      port: this.config.port,
      useSSL: this.config.useSSL,
      accessKey: this.config.accessKey,
      secretKey: this.config.secretKey,
    });
    this.logger.log(`MinIO client initialized → ${this.config.endpoint}:${this.config.port}`);
  }

  async uploadImage(buffer: Buffer, mime: string, userId: string): Promise<UploadResult> {
    this.validateImageMagicBytes(buffer);
    if (buffer.length > 10 * 1024 * 1024) {
      throw new Error('Image size exceeds 10MB limit');
    }
    const ext = mime === 'image/png' ? 'png' : 'jpg';
    const key = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;
    await this.putObject(this.config.bucketProfiles, key, buffer, mime);
    return { url: this.config.buildPublicUrl(this.config.bucketProfiles, key), key };
  }

  async uploadVideo(buffer: Buffer, mime: string, userId: string): Promise<UploadResult> {
    if (buffer.length > 100 * 1024 * 1024) {
      throw new Error('Video size exceeds 100MB limit');
    }
    const ext = mime.split('/')[1] ?? 'mp4';
    const key = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;
    await this.putObject(this.config.bucketMedia, key, buffer, mime);
    return { url: this.config.buildPublicUrl(this.config.bucketMedia, key), key };
  }

  async uploadAudio(buffer: Buffer, mime: string, userId: string): Promise<UploadResult> {
    if (buffer.length > 50 * 1024 * 1024) {
      throw new Error('Audio size exceeds 50MB limit');
    }
    const ext = mime.split('/')[1] ?? 'm4a';
    const key = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;
    await this.putObject(this.config.bucketAudio, key, buffer, mime);
    // Audio bucket is private — return presigned URL valid 1h
    const url = await this.client.presignedGetObject(this.config.bucketAudio, key, 3600);
    return { url, key };
  }

  async deleteFile(bucket: string, key: string, userId: string): Promise<void> {
    if (!key.startsWith(`${userId}/`)) {
      throw new Error('Ownership check failed: key does not belong to this user');
    }
    try {
      await this.client.removeObject(bucket, key);
    } catch (err) {
      this.logger.error(`MediaService.deleteFile failed: ${bucket}/${key}`, err);
      throw err;
    }
  }

  private async putObject(
    bucket: string,
    key: string,
    buffer: Buffer,
    contentType: string,
  ): Promise<void> {
    try {
      await this.client.putObject(bucket, key, buffer, buffer.length, {
        'Content-Type': contentType,
      });
    } catch (err) {
      this.logger.error(`MediaService.putObject failed: ${bucket}/${key}`, err);
      throw err;
    }
  }

  private validateImageMagicBytes(buffer: Buffer): void {
    if (buffer.length < 4) throw new Error('File too small');
    const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
    const isPng = buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47;
    const isWebp = buffer[0] === 0x52 && buffer[1] === 0x49 && buffer[2] === 0x46 && buffer[3] === 0x46;
    if (!isJpeg && !isPng && !isWebp) {
      throw new Error('Invalid image format. Only JPEG, PNG, and WebP are allowed.');
    }
  }
}
