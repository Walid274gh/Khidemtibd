import { Injectable } from '@nestjs/common';

@Injectable()
export class MinioConfigService {
  get endpoint(): string {
    return process.env['MINIO_ENDPOINT'] ?? 'minio';
  }

  get port(): number {
    return parseInt(process.env['MINIO_PORT'] ?? '9001', 10);
  }

  get useSSL(): boolean {
    return process.env['MINIO_USE_SSL'] === 'true';
  }

  get accessKey(): string {
    return process.env['MINIO_ACCESS_KEY'] ?? '';
  }

  get secretKey(): string {
    return process.env['MINIO_SECRET_KEY'] ?? '';
  }

  get bucketProfiles(): string {
    return process.env['MINIO_BUCKET_PROFILES'] ?? 'profile-images';
  }

  get bucketMedia(): string {
    return process.env['MINIO_BUCKET_MEDIA'] ?? 'service-media';
  }

  get bucketAudio(): string {
    return process.env['MINIO_BUCKET_AUDIO'] ?? 'audio-recordings';
  }

  get publicUrl(): string {
    return process.env['MINIO_PUBLIC_URL'] ?? 'http://localhost:9001';
  }

  buildPublicUrl(bucket: string, key: string): string {
    return `${this.publicUrl}/${bucket}/${key}`;
  }
}
