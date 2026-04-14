// apps/api/src/modules/media/media.controller.ts
//
// ARCHITECTURE — proxy NestJS pour MinIO
//
// Routes :
//
//   GET  /media/object/*           → proxy public (pas d'auth — UUID non-devinable)
//                                    Streams l'objet MinIO directement.
//                                    Utilisé pour afficher images/vidéos/audio dans Flutter.
//
//   POST /media/upload/image       → upload image (auth requis) → UploadResult
//   POST /media/upload/video       → upload vidéo (auth requis) → UploadResult
//   POST /media/upload/audio       → upload audio (auth requis) → UploadResult
//
//   DELETE /media/object/*         → suppression par storedPath (auth requis)
//   DELETE /media/:bucket/:key     → suppression legacy (auth requis, maintenu pour compat)
//
// NOTE sur l'ordre des routes :
//   Les routes littérales (object/*) sont déclarées AVANT les routes
//   paramétriques (:bucket/:key) pour éviter toute ambiguïté Express.
//
// NOTE sur @Res() :
//   Les méthodes utilisant @Res() bypassent le ResponseInterceptor global
//   (qui enveloppe en { success, data }). C'est le comportement voulu pour
//   le streaming binaire — on renvoie directement les octets MinIO.

import {
  BadRequestException,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Req,
  Res,
  Param,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Request, Response } from 'express';
import { FirebaseAuthGuard } from '../../common/guards/firebase-auth.guard';
import { CurrentUser }       from '../../common/decorators/current-user.decorator';
import { AuthUser }          from '../../common/guards/firebase-auth.guard';
import { MediaService, UploadResult } from './media.service';

@Controller('media')
export class MediaController {
  constructor(private readonly mediaService: MediaService) {}

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC — GET /media/object/*
  //
  // Stream un objet MinIO à travers NestJS.
  //
  // SÉCURITÉ :
  //   Pas de FirebaseAuthGuard sur cette route.
  //   Raison : les chemins contiennent un UUID aléatoire (non-devinable).
  //   Comportement identique aux CDN publics (Cloudinary, S3 public bucket…).
  //   Upload et suppression restent protégés par Firebase Auth.
  //
  // CACHE :
  //   Cache-Control: public, max-age=31536000, immutable
  //   Les clés contenant un UUID ne changent jamais → cache permanent valide.
  //   Cloudflare mettra également en cache ces réponses côté edge.
  //
  // USAGE Flutter :
  //   Image.network(MediaPathHelper.toUrl(storedPath, apiBaseUrl: _baseUrl))
  //   CachedNetworkImage(imageUrl: MediaPathHelper.toUrl(storedPath, ...))
  // ══════════════════════════════════════════════════════════════════════════

  /**
   * GET /media/object/:storedPath(*)
   *
   * [storedPath] = tout ce qui suit /media/object/ — ex:
   *   service-media/userId/1234567890_uuid.jpg
   *   profile-images/userId/1234567890_uuid.png
   *   audio-recordings/userId/1234567890_uuid.m4a
   */
  @Get('object/*')
  async proxyObject(
    @Req() req: Request,
    @Res() res: Response,
  ): Promise<void> {
    // params['0'] contient tout ce qui suit le préfixe littéral "object/"
    const storedPath = (req.params as Record<string, string>)['0'] ?? '';

    if (!storedPath) {
      res.status(400).json({ success: false, message: 'Missing media path' });
      return;
    }

    return this.mediaService.proxyObject(storedPath, res);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AUTHENTICATED UPLOADS
  // ══════════════════════════════════════════════════════════════════════════

  /**
   * POST /media/upload/image
   * Body: multipart/form-data, champ "file" (JPEG / PNG / WebP, max 10 MB)
   *
   * Réponse UploadResult (enveloppée par ResponseInterceptor) :
   *   { url, key, storedPath }
   *
   * IMPORTANT : persister storedPath dans MongoDB, pas url.
   */
  @Post('upload/image')
  @HttpCode(HttpStatus.OK)
  @UseGuards(FirebaseAuthGuard)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 10 * 1024 * 1024 } }))
  async uploadImage(
    @UploadedFile() file: Express.Multer.File | undefined,
    @CurrentUser() user: AuthUser,
  ): Promise<UploadResult> {
    if (!file?.buffer?.length) throw new BadRequestException('file is required');
    return this.mediaService.uploadImage(file.buffer, file.mimetype, user.uid);
  }

  /**
   * POST /media/upload/video
   * Body: multipart/form-data, champ "file" (MP4 / MOV…, max 100 MB)
   */
  @Post('upload/video')
  @HttpCode(HttpStatus.OK)
  @UseGuards(FirebaseAuthGuard)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 100 * 1024 * 1024 } }))
  async uploadVideo(
    @UploadedFile() file: Express.Multer.File | undefined,
    @CurrentUser() user: AuthUser,
  ): Promise<UploadResult> {
    if (!file?.buffer?.length) throw new BadRequestException('file is required');
    return this.mediaService.uploadVideo(file.buffer, file.mimetype, user.uid);
  }

  /**
   * POST /media/upload/audio
   * Body: multipart/form-data, champ "file" (M4A / WAV / MP3…, max 50 MB)
   */
  @Post('upload/audio')
  @HttpCode(HttpStatus.OK)
  @UseGuards(FirebaseAuthGuard)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 50 * 1024 * 1024 } }))
  async uploadAudio(
    @UploadedFile() file: Express.Multer.File | undefined,
    @CurrentUser() user: AuthUser,
  ): Promise<UploadResult> {
    if (!file?.buffer?.length) throw new BadRequestException('file is required');
    return this.mediaService.uploadAudio(file.buffer, file.mimetype, user.uid);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AUTHENTICATED DELETES
  // ══════════════════════════════════════════════════════════════════════════

  /**
   * DELETE /media/object/*
   *
   * Suppression par storedPath — ENDPOINT PRÉFÉRÉ.
   * [storedPath] = "bucket/userId/timestamp_uuid.ext"
   *
   * Ownership check : la clé doit commencer par "${uid}/".
   */
  @Delete('object/*')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(FirebaseAuthGuard)
  async deleteByPath(
    @Req()         req: Request,
    @CurrentUser() user: AuthUser,
  ): Promise<void> {
    const storedPath = (req.params as Record<string, string>)['0'] ?? '';
    if (!storedPath) throw new BadRequestException('Missing media path');
    return this.mediaService.deleteByStoredPath(storedPath, user.uid);
  }

  /**
   * DELETE /media/:bucket/:key
   *
   * @deprecated Utiliser DELETE /media/object/* à la place.
   * Maintenu pour compatibilité avec l'ancienne API Flutter.
   * Limité aux clés sans "/" (utiliser l'endpoint wilcard pour les sous-dossiers).
   */
  @Delete(':bucket/:key')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(FirebaseAuthGuard)
  async deleteFile(
    @Param('bucket') bucket: string,
    @Param('key')    key: string,
    @CurrentUser()   user: AuthUser,
  ): Promise<void> {
    return this.mediaService.deleteFile(bucket, decodeURIComponent(key), user.uid);
  }
}
