// apps/api/src/modules/media/media.service.ts
//
// ARCHITECTURE — NestJS as MinIO proxy
//
// PROBLÈME RÉSOLU :
//   Les presigned URLs (BUG 2 FIX original) pointaient vers le MinIO interne.
//   Un téléphone accessible via Cloudflare Tunnel ne peut jamais joindre
//   http://minio:9001 ou http://192.168.x.x:9001.
//   De plus, tout changement de domaine Cloudflare invalidait TOUTES les URLs
//   stockées en base.
//
// SOLUTION DÉFINITIVE — proxy NestJS :
//   Flutter → GET https://[cloudflare].com/media/object/bucket/userId/file.jpg
//                  ↓  (même domaine que l'API, un seul tunnel Cloudflare)
//             NestJS reçoit, interroge MinIO en interne (réseau Docker)
//                  ↓
//             http://minio:9001  (privé, jamais exposé)
//
// CHANGEMENT DE PARADIGME — storedPath vs URL :
//   AVANT : stocker l'URL complète en base → brisée dès que le domaine change.
//   APRÈS : stocker "bucket/userId/file.jpg" (storedPath) → durable à vie.
//           MediaPathHelper.toUrl(storedPath, apiBaseUrl: currentUrl) reconstruit
//           l'URL dynamiquement à chaque affichage.
//
// INTERFACE UploadResult :
//   • url        : URL proxy complète pour usage immédiat (domain-dependent)
//   • key        : clé dans le bucket (userId/timestamp_uuid.ext)
//   • storedPath : "bucket/key" — PERSISTER CECI en base, pas url

import {
  BadRequestException,
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { Response } from 'express';
import * as Minio from 'minio';
import { randomUUID } from 'crypto';
import { MinioConfigService } from '../../config/minio.config';

// ── Public interface ──────────────────────────────────────────────────────────

export interface UploadResult {
  /**
   * URL proxy NestJS → immédiatement utilisable mais dépendante du domaine.
   * Construit à partir de API_BASE_URL au moment de l'upload.
   * NE PAS persister en base — utiliser storedPath.
   */
  url: string;

  /** Clé de l'objet dans son bucket. Ex: "userId/1234567890_uuid.jpg" */
  key: string;

  /**
   * Chemin durable: "bucketName/objectKey".
   * Ex: "service-media/userId/1234567890_uuid.jpg"
   *
   * PERSISTER CECI dans MongoDB (mediaUrls, profileImageUrl…).
   * Reconstruire l'URL avec MediaPathHelper.toUrl(storedPath, apiBaseUrl: …).
   * Survit à tout changement de domaine Cloudflare.
   */
  storedPath: string;
}

// ── Service ───────────────────────────────────────────────────────────────────

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
    this.logger.log(
      `✅ MinIO client initialized → ${this.config.endpoint}:${this.config.port}`,
    );
  }

  // ── Upload methods ────────────────────────────────────────────────────────

  async uploadImage(
    buffer: Buffer,
    mime: string,
    userId: string,
  ): Promise<UploadResult> {
    this.validateImageMagicBytes(buffer);
    if (buffer.length > 10 * 1024 * 1024) {
      throw new BadRequestException('Image size exceeds 10 MB limit');
    }

    const ext    = this.imageExtension(mime);
    const key    = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;
    const bucket = this.config.bucketProfiles;

    await this.putObject(bucket, key, buffer, mime);

    const storedPath = `${bucket}/${key}`;
    return { url: this.buildProxyUrl(storedPath), key, storedPath };
  }

  async uploadVideo(
    buffer: Buffer,
    mime: string,
    userId: string,
  ): Promise<UploadResult> {
    if (buffer.length > 100 * 1024 * 1024) {
      throw new BadRequestException('Video size exceeds 100 MB limit');
    }

    const ext    = mime.split('/')[1] ?? 'mp4';
    const key    = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;
    const bucket = this.config.bucketMedia;

    await this.putObject(bucket, key, buffer, mime);

    const storedPath = `${bucket}/${key}`;
    return { url: this.buildProxyUrl(storedPath), key, storedPath };
  }

  async uploadAudio(
    buffer: Buffer,
    mime: string,
    userId: string,
  ): Promise<UploadResult> {
    if (buffer.length > 50 * 1024 * 1024) {
      throw new BadRequestException('Audio size exceeds 50 MB limit');
    }

    const ext    = mime.split('/')[1] ?? 'm4a';
    const key    = `${userId}/${Date.now()}_${randomUUID()}.${ext}`;
    const bucket = this.config.bucketAudio;

    await this.putObject(bucket, key, buffer, mime);

    const storedPath = `${bucket}/${key}`;
    return { url: this.buildProxyUrl(storedPath), key, storedPath };
  }

  // ── Proxy method ──────────────────────────────────────────────────────────

  /**
   * Lit l'objet MinIO identifié par storedPath ("bucket/key") et
   * le stream directement dans la Response Express.
   *
   * Appelé par GET /media/object/* — aucun auth requis (UUID non-devinable).
   * Headers renvoyés : Content-Type, Content-Length, ETag, Cache-Control.
   * Cache immutable 1 an car les clés contiennent un UUID unique.
   */
  async proxyObject(storedPath: string, res: Response): Promise<void> {
    const slashIdx = storedPath.indexOf('/');
    if (slashIdx === -1) {
      res.status(400).json({ success: false, message: 'Invalid media path format' });
      return;
    }

    const bucket = storedPath.substring(0, slashIdx);
    const key    = storedPath.substring(slashIdx + 1);

    if (!key) {
      res.status(400).json({ success: false, message: 'Missing object key in path' });
      return;
    }

    try {
      const stat        = await this.client.statObject(bucket, key);
      const stream      = await this.client.getObject(bucket, key);
      const contentType = (stat.metaData?.['content-type'] as string | undefined)
                       ?? this.guessContentType(key);

      res.setHeader('Content-Type',   contentType);
      res.setHeader('Content-Length', stat.size);
      res.setHeader('ETag',           `"${stat.etag}"`);
      res.setHeader('Cache-Control',  'public, max-age=31536000, immutable');
      if (stat.lastModified) {
        res.setHeader('Last-Modified', stat.lastModified.toUTCString());
      }
      res.status(200);

      stream.pipe(res);

      stream.on('error', (err: Error) => {
        this.logger.error(`Stream error for "${storedPath}": ${err.message}`);
        if (!res.headersSent) res.status(500).end();
      });
    } catch (err) {
      const code = (err as Record<string, unknown>)?.['code'] as string | undefined;
      if (code === 'NoSuchKey' || code === 'NotFound') {
        this.logger.warn(`Proxy 404: ${storedPath}`);
        res.status(404).json({ success: false, message: 'Media not found' });
      } else {
        this.logger.error(`Proxy error for "${storedPath}"`, err);
        res.status(502).json({ success: false, message: 'Storage service unavailable' });
      }
    }
  }

  // ── Delete methods ────────────────────────────────────────────────────────

  /**
   * Supprime l'objet identifié par storedPath ("bucket/key").
   * Vérifie l'ownership : la clé doit commencer par "${userId}/".
   * Utilisé par DELETE /media/object/*  (nouveau endpoint préféré).
   */
  async deleteByStoredPath(storedPath: string, userId: string): Promise<void> {
    const slashIdx = storedPath.indexOf('/');
    if (slashIdx === -1) {
      throw new BadRequestException('Invalid stored path format');
    }

    const bucket = storedPath.substring(0, slashIdx);
    const key    = storedPath.substring(slashIdx + 1);

    return this.deleteFile(bucket, key, userId);
  }

  /**
   * Supprime un objet par bucket + key séparés.
   * Utilisé par DELETE /media/:bucket/:key  (endpoint legacy, maintenu pour
   * compatibilité ascendante).
   */
  async deleteFile(bucket: string, key: string, userId: string): Promise<void> {
    if (!key.startsWith(`${userId}/`)) {
      throw new BadRequestException(
        'Ownership check failed: key does not belong to this user',
      );
    }
    try {
      await this.client.removeObject(bucket, key);
    } catch (err) {
      this.logger.error(`MediaService.deleteFile failed: ${bucket}/${key}`, err);
      throw err;
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /**
   * Construit l'URL proxy à partir de API_BASE_URL (variable d'environnement).
   * Cette URL change avec le tunnel Cloudflare — ne pas persister en base.
   * Persister storedPath et reconstruire via MediaPathHelper.toUrl() côté Flutter.
   */
  private buildProxyUrl(storedPath: string): string {
    const base = (
      process.env['API_BASE_URL'] ??
      `http://localhost:${process.env['PORT'] ?? 3000}`
    ).replace(/\/$/, '');
    return `${base}/media/object/${storedPath}`;
  }

  private imageExtension(mime: string): string {
    if (mime === 'image/png')  return 'png';
    if (mime === 'image/webp') return 'webp';
    if (mime === 'image/gif')  return 'gif';
    return 'jpg';
  }

  private guessContentType(key: string): string {
    const ext = key.split('.').pop()?.toLowerCase() ?? '';
    const map: Record<string, string> = {
      jpg:  'image/jpeg',
      jpeg: 'image/jpeg',
      png:  'image/png',
      gif:  'image/gif',
      webp: 'image/webp',
      mp4:  'video/mp4',
      mov:  'video/quicktime',
      avi:  'video/x-msvideo',
      mkv:  'video/x-matroska',
      mp3:  'audio/mpeg',
      wav:  'audio/wav',
      m4a:  'audio/mp4',
      ogg:  'audio/ogg',
      flac: 'audio/flac',
    };
    return map[ext] ?? 'application/octet-stream';
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
    if (buffer.length < 4) throw new BadRequestException('File too small');

    const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
    const isPng  =
      buffer[0] === 0x89 && buffer[1] === 0x50 &&
      buffer[2] === 0x4e && buffer[3] === 0x47;
    const isWebp =
      buffer.length >= 12 &&
      buffer[0] === 0x52 && buffer[1] === 0x49 &&
      buffer[2] === 0x46 && buffer[3] === 0x46 &&
      buffer[8] === 0x57 && buffer[9] === 0x45 &&
      buffer[10] === 0x42 && buffer[11] === 0x50;

    if (!isJpeg && !isPng && !isWebp) {
      throw new BadRequestException(
        'Invalid image format. Only JPEG, PNG, and WebP are allowed.',
      );
    }
  }
}
