// apps/api/src/modules/users/users.controller.ts
//
// FIX Bug 2 — لا تنشئ stub تلقائياً عند GET /users/:id.
//
// المشكلة السابقة:
//   findById() كانت تستدعي ensureExists() والتي تنشئ وثيقة client في MongoDB
//   فور أول طلب GET. هذا يتعارض مع تسجيل العامل:
//     1. phone auth → Flutter تستدعي GET /users/:id (لفحص الملف)
//     2. ensureExists() تنشئ stub باسم "User" ودور "client"
//     3. تسجيل العامل يفشل (Bug 1) → يُغلق التطبيق
//     4. عند إعادة الفتح: الـ stub موجودة → role=client → يذهب للـ home
//
// الحل:
//   استخدم findById() الصارمة — ترجع 404 إذا لم توجد الوثيقة.
//   Flutter تعامل 404 كـ null في getUser() بشكل صحيح.
//   المستخدمون الجدد: 404 → null → checkAuthUser يُعيد isNewUser=true → setup flow
//   المستخدمون العائدون: وثيقتهم موجودة → fetch طبيعي
//
// ملاحظة: إذا احتجت يوماً لـ auto-provisioning، افعلها في POST /users فقط.

import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  HttpCode,
  HttpStatus,
  Logger,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { FirebaseAuthGuard } from '../../common/guards/firebase-auth.guard';
import { CurrentUser }       from '../../common/decorators/current-user.decorator';
import { AuthUser }          from '../../common/guards/firebase-auth.guard';
import { UsersService }      from './users.service';
import { CreateUserDto }     from '../../dto/create-user.dto';
import { UpdateUserDto }     from '../../dto/update-user.dto';
import { UpdateLocationDto } from '../../dto/update-location.dto';
import { UpdateFcmTokenDto } from '../../dto/update-fcm-token.dto';
import { UserDocument }      from '../../schemas/user.schema';

@Controller('users')
@UseGuards(FirebaseAuthGuard)
export class UsersController {
  private readonly logger = new Logger(UsersController.name);

  constructor(private readonly usersService: UsersService) {}

  /** POST /users — create or update caller's profile (client or worker). */
  @Post()
  @HttpCode(HttpStatus.OK)
  async upsert(
    @Body() dto: CreateUserDto,
    @CurrentUser() user: AuthUser,
  ): Promise<UserDocument> {
    if (dto.id !== user.uid) throw new ForbiddenException('You can only create your own profile');
    return this.usersService.upsert(dto);
  }

  /**
   * GET /users/:id
   *
   * FIX: يستخدم findById() الصارمة — لا auto-provisioning.
   * ترجع 404 إذا لم توجد الوثيقة. Flutter تعامل هذا كـ null.
   *
   * السبب: ensureExists() كانت تنشئ stub من نوع client قبل أن يختار
   * المستخدم دوره، مما يُفسد flow تسجيل العامل.
   */
  @Get(':id')
  async findById(
    @Param('id') id: string,
    @CurrentUser() _user: AuthUser,
  ): Promise<UserDocument> {
    return this.usersService.findById(id);
  }

  @Patch(':id')
  async update(
    @Param('id') id: string,
    @Body() dto: UpdateUserDto,
    @CurrentUser() user: AuthUser,
  ): Promise<UserDocument> {
    if (id !== user.uid) throw new ForbiddenException('You can only update your own profile');
    return this.usersService.update(id, dto);
  }

  @Patch(':id/location')
  @HttpCode(HttpStatus.NO_CONTENT)
  async updateLocation(
    @Param('id') id: string,
    @Body() dto: UpdateLocationDto,
    @CurrentUser() user: AuthUser,
  ): Promise<void> {
    if (id !== user.uid) throw new ForbiddenException('You can only update your own location');
    return this.usersService.updateLocation(
      id, dto.latitude, dto.longitude, dto.cellId, dto.wilayaCode, dto.geoHash,
    );
  }

  @Patch(':id/fcm-token')
  @HttpCode(HttpStatus.NO_CONTENT)
  async updateFcmToken(
    @Param('id') id: string,
    @Body() dto: UpdateFcmTokenDto,
    @CurrentUser() user: AuthUser,
  ): Promise<void> {
    if (id !== user.uid) throw new ForbiddenException('You can only update your own FCM token');
    return this.usersService.updateFcmToken(id, dto.fcmToken);
  }
}
