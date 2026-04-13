// apps/api/src/modules/users/users.controller.ts
//
// CHANGE vs original: findById() now calls usersService.ensureExists() when
// the authenticated user queries their own uid.
//
// WHY HERE and not in the service layer:
//   The auto-provisioning decision requires two pieces of context that only
//   exist at the controller/request level:
//     1. The authenticated uid (from @CurrentUser())
//     2. The token claims (email, displayName) for the stub
//
//   Keeping it in the controller preserves the service layer's single
//   responsibility: pure domain logic.  The controller handles the HTTP
//   request semantics (who is asking, and for what).
//
// SECURITY:
//   ensureExists() is ONLY called when id === user.uid, i.e. the requester
//   is asking for their own profile.  Querying another user's profile still
//   goes through findById() and returns 404 if not found — no auto-provision
//   for third-party lookups.

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
   * When the authenticated user requests their OWN profile and it is absent
   * from MongoDB, we auto-provision a minimal stub from the Firebase token
   * claims instead of returning 404.
   *
   * Scenario: Firebase Auth account exists (JWT valid) but the POST /users
   * call during registration never reached the server (network failure, app
   * killed, timeout).  Without this guard the entire service-request creation
   * flow fails because the form controller calls GET /users/:uid to prefill
   * the name and phone number.
   *
   * For any uid OTHER than the caller's own, behaviour is unchanged: 404 if
   * not found.
   */
  @Get(':id')
  async findById(
    @Param('id') id: string,
    @CurrentUser() user: AuthUser,
  ): Promise<UserDocument> {
    if (id === user.uid) {
      // Auto-provision path: returns existing doc or creates a stub.
      return this.usersService.ensureExists(id, {
        name:  user.name,
        email: user.email,
      });
    }
    // Third-party lookup: strict, no auto-provision.
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
