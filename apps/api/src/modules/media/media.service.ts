// apps/api/src/modules/media/media.service.ts
//
// BUG 2 FIX — Médias inaccessibles (images et vidéos)
//
// PROBLÈME :
//   MinioConfigService.publicUrl retourne 'http://localhost:9001' (valeur par
//   défaut). Un téléphone physique ne peut pas résoudre ce hostname. De plus,
//   les buckets MinIO n'ont pas de politique d'accès public — un GET
//   non-authentifié retourne 403.
//
// SOLUTION :
//   • uploadImage() et uploadVideo() utilisent désormais des presigned URLs
//     (valides 7 jours) au lieu de buildPublicUrl().
//   • uploadAudio() utilisait déjà presignedGetObject (1h) — inchangé.
//   • Les presigned URLs fonctionnent depuis n'importe quel réseau,
//     indépendamment de MINIO_PUBLIC_URL et des policies de bucket.
//
// NOTE ARCHITECTURALE :
//   Les presigned URLs expirent. Pour une production pérenne, stocker
//   uniquement le `key` en base et régénérer la presigned URL à chaque lecture
//   via un endpoint /media/presign/:key. C'est le pattern correct pour MinIO.

import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import * as Minio from 'minio';
import { randomUUID } from 'crypto';
import { MinioConfigService } from '../../config/minio.config';

export interface UploadResult {
  url: string;
  key: string;
}

/** Durée de validité des presigned URLs image et vidéo : 7 jours en secondes */
const PRESIGNED_URL_TTL_SECONDS = 7 * 24 * 3600; // 604 800 s

/** Durée de validité des presigned URLs audio : 1 heure en secondes */
const PRESIGNED_AUDIO_TTL_SECONDS = 3600; // 1 h

@Injectable()
export class MediaService implements OnModuleInit {
  private readonly logger = new Logger(MediaService.name);
  private client!: Minio.Client;

  constructor(private readonly config: MinioConfigService) {}

  onModuleInit(): void {
    this.client = new Minio.Client({
      endPoint:  this.config.endpoint,
      port:      this.config.port,
      useSSL:    this.config.useSSL,
      accessKey: this.config.accessKey,
      secretKey: this.config.secretKey,
    });
    this.logger.log(`MinIO client initialized → ${this.config.endpoint}:${this.config.port}`);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUG 2 FIX — uploadImage
  //
  // AVANT : return { url: this.config.buildPublicUrl(bucket, key), key };
  //   → URL localhost:9001 inaccessible depuis un téléphone physique
  //
  // APRÈS : presigned GET URL valable 7 jours, indépendante du réseau
  // ─────────────────────────────────────────────────────────────────────────
  async uploadImage(buffer: Buffer, mime: string, userId: string): Promise<UploadResult> {
    this.validateImageMagicBytes(buffer);
    if (buffer.length > 10 * 1024 * 1024) {
      throw new Error('Image size exceeds 10MB limit');
    }

    const ext = mime === 'image/png' ? 'png' : 'jpg';
    const key = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;

    await this.putObject(this.config.bucketProfiles, key, buffer, mime);

    // BUG 2 FIX: presigned URL 7 jours — fonctionne depuis n'importe quel
    // réseau, indépendant de MINIO_PUBLIC_URL et des policies de bucket.
    const url = await this.client.presignedGetObject(
      this.config.bucketProfiles,
      key,
      PRESIGNED_URL_TTL_SECONDS,
    );

    return { url, key };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUG 2 FIX — uploadVideo
  //
  // Même correction que uploadImage : presigned URL au lieu de buildPublicUrl.
  // ─────────────────────────────────────────────────────────────────────────
  async uploadVideo(buffer: Buffer, mime: string, userId: string): Promise<UploadResult> {
    if (buffer.length > 100 * 1024 * 1024) {
      throw new Error('Video size exceeds 100MB limit');
    }

    const ext = mime.split('/')[1] ?? 'mp4';
    const key = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;

    await this.putObject(this.config.bucketMedia, key, buffer, mime);

    // BUG 2 FIX: presigned URL 7 jours — même approche que uploadImage.
    const url = await this.client.presignedGetObject(
      this.config.bucketMedia,
      key,
      PRESIGNED_URL_TTL_SECONDS,
    );

    return { url, key };
  }

  // uploadAudio était déjà correct (presigned 1h) — inchangé.
  async uploadAudio(buffer: Buffer, mime: string, userId: string): Promise<UploadResult> {
    if (buffer.length > 50 * 1024 * 1024) {
      throw new Error('Audio size exceeds 50MB limit');
    }
    const ext = mime.split('/')[1] ?? 'm4a';
    const key = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;
    await this.putObject(this.config.bucketAudio, key, buffer, mime);
    // Audio bucket est privé — presigned URL 1h
    const url = await this.client.presignedGetObject(
      this.config.bucketAudio,
      key,
      PRESIGNED_AUDIO_TTL_SECONDS,
    );
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
    const isPng  = buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47;
    // WebP: RIFF...WEBP
    const isWebp = buffer.length >= 12
      && buffer[0] === 0x52 && buffer[1] === 0x49 && buffer[2] === 0x46 && buffer[3] === 0x46
      && buffer[8] === 0x57 && buffer[9] === 0x45 && buffer[10] === 0x42 && buffer[11] === 0x50;
    if (!isJpeg && !isPng && !isWebp) {
      throw new Error('Invalid image format. Only JPEG, PNG, and WebP are allowed.');
    }
  }
}
