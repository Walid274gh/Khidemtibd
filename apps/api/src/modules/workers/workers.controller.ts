import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { FirebaseAuthGuard } from '../../common/guards/firebase-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AuthUser } from '../../common/guards/firebase-auth.guard';
import { WorkersService } from './workers.service';
import { CreateWorkerDto } from '../../dto/create-worker.dto';
import { UpdateWorkerDto } from '../../dto/update-worker.dto';
import { UpdateLocationDto } from '../../dto/update-location.dto';
import { UpdateFcmTokenDto } from '../../dto/update-fcm-token.dto';
import { UpdateWorkerStatusDto } from '../../dto/update-worker-status.dto';
import { WorkerDocument } from '../../schemas/worker.schema';

@Controller('workers')
@UseGuards(FirebaseAuthGuard)
export class WorkersController {
  constructor(private readonly workersService: WorkersService) {}

  /**
   * POST /workers
   * Create or update the caller's worker profile.
   */
  @Post()
  @HttpCode(HttpStatus.OK)
  async upsert(
    @Body() dto: CreateWorkerDto,
    @CurrentUser() user: AuthUser,
  ): Promise<WorkerDocument> {
    if (dto.id !== user.uid) {
      throw new ForbiddenException('You can only create your own worker profile');
    }
    return this.workersService.upsert(dto);
  }

  /**
   * GET /workers
   * List workers with optional filters: wilayaCode, profession, isOnline, cellId.
   */
  @Get()
  async findMany(
    @Query('wilayaCode') wilayaCodeStr?: string,
    @Query('profession') profession?: string,
    @Query('isOnline') isOnlineStr?: string,
    @Query('cellId') cellId?: string,
    @Query('limit') limitStr?: string,
  ): Promise<WorkerDocument[]> {
    const wilayaCode = wilayaCodeStr ? parseInt(wilayaCodeStr, 10) : undefined;
    const isOnline   = isOnlineStr !== undefined ? isOnlineStr === 'true' : undefined;
    const limit      = limitStr ? Math.min(parseInt(limitStr, 10), 200) : 100;

    return this.workersService.findMany({ wilayaCode, profession, isOnline, cellId, limit });
  }

  /**
   * GET /workers/:id
   * Fetch a worker profile.
   */
  @Get(':id')
  async findById(@Param('id') id: string): Promise<WorkerDocument> {
    return this.workersService.findById(id);
  }

  /**
   * PATCH /workers/:id
   * Update the caller's own worker profile.
   */
  @Patch(':id')
  async update(
    @Param('id') id: string,
    @Body() dto: UpdateWorkerDto,
    @CurrentUser() user: AuthUser,
  ): Promise<WorkerDocument> {
    if (id !== user.uid) {
      throw new ForbiddenException('You can only update your own profile');
    }
    return this.workersService.update(id, dto);
  }

  /**
   * PATCH /workers/:id/status
   * Toggle online/offline status.
   */
  @Patch(':id/status')
  @HttpCode(HttpStatus.NO_CONTENT)
  async updateStatus(
    @Param('id') id: string,
    @Body() dto: UpdateWorkerStatusDto,
    @CurrentUser() user: AuthUser,
  ): Promise<void> {
    if (id !== user.uid) {
      throw new ForbiddenException('You can only update your own status');
    }
    return this.workersService.updateStatus(id, dto.isOnline);
  }

  /**
   * PATCH /workers/:id/location
   * Update GPS coordinates. Optionally include cellId, wilayaCode, geoHash
   * when the client has already computed geographic cell assignment.
   */
  @Patch(':id/location')
  @HttpCode(HttpStatus.NO_CONTENT)
  async updateLocation(
    @Param('id') id: string,
    @Body() dto: UpdateLocationDto,
    @CurrentUser() user: AuthUser,
  ): Promise<void> {
    if (id !== user.uid) {
      throw new ForbiddenException('You can only update your own location');
    }
    return this.workersService.updateLocation(
      id,
      dto.latitude,
      dto.longitude,
      dto.cellId,
      dto.wilayaCode,
      dto.geoHash,
    );
  }

  /**
   * PATCH /workers/:id/fcm-token
   * Update push notification token.
   */
  @Patch(':id/fcm-token')
  @HttpCode(HttpStatus.NO_CONTENT)
  async updateFcmToken(
    @Param('id') id: string,
    @Body() dto: UpdateFcmTokenDto,
    @CurrentUser() user: AuthUser,
  ): Promise<void> {
    if (id !== user.uid) {
      throw new ForbiddenException('You can only update your own FCM token');
    }
    return this.workersService.updateFcmToken(id, dto.fcmToken);
  }
}
