import {
  Controller,
  Post,
  Body,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  BadRequestException,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { FirebaseAuthGuard } from '../../common/guards/firebase-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AuthUser } from '../../common/guards/firebase-auth.guard';
import { IntentExtractorService, SearchIntent } from './services/intent-extractor.service';

class ExtractTextDto {
  text!: string;
}

@Controller('ai')
@UseGuards(FirebaseAuthGuard)
export class AiController {
  constructor(private readonly intentExtractor: IntentExtractorService) {}

  @Post('extract-intent')
  @HttpCode(HttpStatus.OK)
  async extractIntent(
    @Body() dto: ExtractTextDto,
    @CurrentUser() _user: AuthUser,
  ): Promise<SearchIntent> {
    if (!dto.text?.trim()) {
      throw new BadRequestException('text is required');
    }
    return this.intentExtractor.extractFromText(dto.text.slice(0, 2000));
  }

  @Post('extract-intent/audio')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 50 * 1024 * 1024 } }))
  async extractIntentFromAudio(
    @UploadedFile() file: Express.Multer.File | undefined,
    @CurrentUser() _user: AuthUser,
  ): Promise<SearchIntent> {
    if (!file?.buffer?.length) {
      throw new BadRequestException('audio file is required');
    }
    return this.intentExtractor.extractFromAudio(file.buffer, file.mimetype);
  }

  @Post('extract-intent/image')
  @HttpCode(HttpStatus.OK)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 10 * 1024 * 1024 } }))
  async extractIntentFromImage(
    @UploadedFile() file: Express.Multer.File | undefined,
    @CurrentUser() _user: AuthUser,
  ): Promise<SearchIntent> {
    if (!file?.buffer?.length) {
      throw new BadRequestException('image file is required');
    }
    // Magic bytes validation: JPEG (FF D8 FF) or PNG (89 50 4E 47)
    const b = file.buffer;
    const isJpeg = b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
    const isPng = b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47;
    if (!isJpeg && !isPng) {
      throw new BadRequestException('Only JPEG and PNG images are supported');
    }
    const imageBase64 = file.buffer.toString('base64');
    return this.intentExtractor.extractFromImage(imageBase64);
  }
}
