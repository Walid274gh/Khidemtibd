// apps/api/src/modules/users/users.service.ts
//
// ADDED: ensureExists(uid, claims)
//
// ROOT CAUSE of the "Erreur lors de l'envoi" bug (Image 6):
//   A Firebase Auth account existed (JWT was valid → FirebaseAuthGuard passed),
//   but the corresponding MongoDB document in the 'users' collection had never
//   been created.  This happens when:
//     1. The Flutter app created the Firebase account successfully, AND
//     2. The network call to POST /users (createOrUpdateUser) failed silently
//        during registration (timeout, app killed, no network), OR
//     3. _ensureBackendProfile() in AuthService fired after signIn but the
//        request never reached the server.
//
// FIX STRATEGY — "upsert on demand":
//   UsersController.findById() calls ensureExists() when the requester is
//   querying their own uid.  ensureExists() is idempotent: if the document
//   already exists it is returned unchanged.  If not, a minimal 'client' profile
//   is created from the Firebase token claims (email, displayName).  This is
//   safe because:
//     • The JWT has already been verified by FirebaseAuthGuard.
//     • We only auto-provision for the authenticated user's OWN uid.
//     • The created document has role='client' — correct for a new user.
//     • A subsequent POST /users from the Flutter app will upsert additional
//       fields (phone, profileImageUrl, etc.) over the auto-provisioned stub.

import {
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { FilterQuery, Model } from 'mongoose';
import { User, UserDocument, UserRole } from '../../schemas/user.schema';
import { CreateUserDto }    from '../../dto/create-user.dto';
import { UpdateUserDto }    from '../../dto/update-user.dto';
import { CreateWorkerDto }  from '../../dto/create-worker.dto';
import { UpdateWorkerDto }  from '../../dto/update-worker.dto';

// ── Filter shapes ─────────────────────────────────────────────────────────────

export interface UserFilters {
  role?: UserRole;
  wilayaCode?: number;
  profession?: string;
  isOnline?: boolean;
  cellId?: string;
  limit?: number;
}

export interface ProvisionClaims {
  /** Firebase displayName — used as the account's name. */
  name?: string | undefined;
  /** Firebase email — used as the account's email. */
  email?: string | undefined;
}

// ──────────────────────────────────────────────────────────────────────────────

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    @InjectModel(User.name)
    private readonly userModel: Model<UserDocument>,
  ) {}

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED (client + worker)
  // ═══════════════════════════════════════════════════════════════════════════

  async upsert(dto: CreateUserDto | CreateWorkerDto): Promise<UserDocument> {
    try {
      const role = dto.role ?? UserRole.Client;
      const patch: Partial<Record<string, unknown>> = {
        name:        dto.name,
        email:       dto.email,
        role,
        phoneNumber: dto.phoneNumber ?? '',
        latitude:    dto.latitude    ?? null,
        longitude:   dto.longitude   ?? null,
        profileImageUrl: dto.profileImageUrl ?? null,
        fcmToken:    dto.fcmToken    ?? null,
        lastUpdated: new Date(),
      };

      if ('profession' in dto && dto.profession)       patch['profession'] = dto.profession;
      if ('isOnline'   in dto && dto.isOnline != null) patch['isOnline']   = dto.isOnline;

      const doc = await this.userModel
        .findByIdAndUpdate(dto.id, patch, { upsert: true, new: true, runValidators: true })
        .exec();

      if (!doc) throw new NotFoundException(`User ${dto.id} not found after upsert`);
      return doc;
    } catch (err) {
      this.logger.error('UsersService.upsert failed', err);
      throw err;
    }
  }

  async findById(id: string): Promise<UserDocument> {
    try {
      const doc = await this.userModel.findById(id).exec();
      if (!doc) throw new NotFoundException(`User ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`UsersService.findById(${id}) failed`, err);
      throw err;
    }
  }

  async findByIdOrNull(id: string): Promise<UserDocument | null> {
    return this.userModel.findById(id).exec();
  }

  /**
   * Idempotent "upsert on demand".
   *
   * Returns the existing document unchanged if it already exists.
   * If the user is absent from MongoDB (e.g. profile creation failed during
   * registration), creates a minimal stub from the Firebase token claims.
   *
   * This is the canonical fix for the "Erreur lors de l'envoi" 404 scenario:
   * the JWT is valid (Firebase Auth has the account), but the MongoDB profile
   * was never persisted.
   *
   * @param uid    Firebase UID — used as the document _id.
   * @param claims Decoded token fields (email, displayName) for the stub.
   */
  async ensureExists(uid: string, claims: ProvisionClaims): Promise<UserDocument> {
    // Fast path: document already exists — no write needed.
    const existing = await this.findByIdOrNull(uid);
    if (existing) return existing;

    // Derive a sensible display name from what the token gives us.
    const name =
      claims.name?.trim() ||
      claims.email?.split('@')[0] ||
      'User';

    this.logger.warn(
      `Auto-provisioning missing MongoDB profile for uid=${uid} ` +
      `(email=${claims.email ?? 'unknown'}) — this indicates a registration ` +
      `race condition.  The Flutter app will upsert the full profile shortly.`,
    );

    return this.upsert({
      id:    uid,
      name,
      email: claims.email ?? '',
      role:  UserRole.Client,
      // All other fields take their schema defaults:
      //   phoneNumber: '', latitude: null, longitude: null, etc.
    });
  }

  async findMany(filters: UserFilters): Promise<UserDocument[]> {
    try {
      const query: FilterQuery<User> = {};
      if (filters.role       != null) query.role       = filters.role;
      if (filters.wilayaCode != null) query.wilayaCode = filters.wilayaCode;
      if (filters.profession)         query.profession  = filters.profession;
      if (filters.isOnline   != null) query.isOnline   = filters.isOnline;
      if (filters.cellId)             query.cellId      = filters.cellId;

      const limit = Math.min(filters.limit ?? 100, 200);
      return this.userModel.find(query).limit(limit).exec();
    } catch (err) {
      this.logger.error('UsersService.findMany failed', err);
      throw err;
    }
  }

  async update(id: string, dto: UpdateUserDto): Promise<UserDocument> {
    try {
      const patch: Partial<Record<string, unknown>> = { lastUpdated: new Date() };
      if (dto.name             != null) patch['name']            = dto.name;
      if (dto.phoneNumber      != null) patch['phoneNumber']     = dto.phoneNumber;
      if (dto.profileImageUrl  != null) patch['profileImageUrl'] = dto.profileImageUrl;
      if (dto.cellId           != null) patch['cellId']          = dto.cellId;
      if (dto.wilayaCode       != null) patch['wilayaCode']      = dto.wilayaCode;
      if (dto.geoHash          != null) patch['geoHash']         = dto.geoHash;

      const doc = await this.userModel
        .findByIdAndUpdate(id, patch, { new: true, runValidators: true })
        .exec();
      if (!doc) throw new NotFoundException(`User ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`UsersService.update(${id}) failed`, err);
      throw err;
    }
  }

  async updateLocation(
    id: string,
    latitude: number,
    longitude: number,
    cellId?: string,
    wilayaCode?: number,
    geoHash?: string,
  ): Promise<void> {
    try {
      const patch: Partial<Record<string, unknown>> = {
        latitude,
        longitude,
        lastUpdated: new Date(),
      };
      if (cellId     != null) { patch['cellId']       = cellId;     patch['lastCellUpdate'] = new Date(); }
      if (wilayaCode != null)   patch['wilayaCode']   = wilayaCode;
      if (geoHash    != null)   patch['geoHash']      = geoHash;

      const result = await this.userModel.updateOne({ _id: id }, patch).exec();
      if (result.matchedCount === 0) throw new NotFoundException(`User ${id} not found`);
    } catch (err) {
      this.logger.error(`UsersService.updateLocation(${id}) failed`, err);
      throw err;
    }
  }

  async updateFcmToken(id: string, fcmToken: string): Promise<void> {
    try {
      const result = await this.userModel
        .updateOne({ _id: id }, { fcmToken, lastUpdated: new Date() })
        .exec();
      if (result.matchedCount === 0) throw new NotFoundException(`User ${id} not found`);
    } catch (err) {
      this.logger.error(`UsersService.updateFcmToken(${id}) failed`, err);
      throw err;
    }
  }

  async clearFcmToken(id: string): Promise<void> {
    await this.userModel.updateOne({ _id: id }, { fcmToken: null, lastUpdated: new Date() }).exec();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WORKER API  (all queries enforce role = 'worker')
  // ═══════════════════════════════════════════════════════════════════════════

  async upsertWorker(dto: CreateWorkerDto): Promise<UserDocument> {
    return this.upsert({ ...dto, role: UserRole.Worker });
  }

  async findWorkerById(id: string): Promise<UserDocument> {
    try {
      const doc = await this.userModel
        .findOne({ _id: id, role: UserRole.Worker })
        .exec();
      if (!doc) throw new NotFoundException(`Worker ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`UsersService.findWorkerById(${id}) failed`, err);
      throw err;
    }
  }

  async findWorkerByIdOrNull(id: string): Promise<UserDocument | null> {
    return this.userModel.findOne({ _id: id, role: UserRole.Worker }).exec();
  }

  async findWorkers(filters: Omit<UserFilters, 'role'>): Promise<UserDocument[]> {
    return this.findMany({ ...filters, role: UserRole.Worker });
  }

  async updateWorker(id: string, dto: UpdateWorkerDto): Promise<UserDocument> {
    try {
      const patch: Partial<Record<string, unknown>> = { lastUpdated: new Date() };
      if (dto.name             != null) patch['name']            = dto.name;
      if (dto.phoneNumber      != null) patch['phoneNumber']     = dto.phoneNumber;
      if (dto.profileImageUrl  != null) patch['profileImageUrl'] = dto.profileImageUrl;
      if (dto.cellId           != null) patch['cellId']          = dto.cellId;
      if (dto.wilayaCode       != null) patch['wilayaCode']      = dto.wilayaCode;
      if (dto.geoHash          != null) patch['geoHash']         = dto.geoHash;
      if (dto.averageRating    != null) patch['averageRating']   = dto.averageRating;
      if (dto.ratingCount      != null) patch['ratingCount']     = dto.ratingCount;
      if (dto.jobsCompleted    != null) patch['jobsCompleted']   = dto.jobsCompleted;
      if (dto.responseRate     != null) patch['responseRate']    = dto.responseRate;
      if (dto.lastActiveAt     != null) patch['lastActiveAt']    = dto.lastActiveAt;

      const doc = await this.userModel
        .findOneAndUpdate(
          { _id: id, role: UserRole.Worker },
          patch,
          { new: true, runValidators: true },
        )
        .exec();
      if (!doc) throw new NotFoundException(`Worker ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`UsersService.updateWorker(${id}) failed`, err);
      throw err;
    }
  }

  async updateWorkerStatus(id: string, isOnline: boolean): Promise<void> {
    try {
      const patch: Partial<Record<string, unknown>> = {
        isOnline,
        lastUpdated: new Date(),
      };
      if (!isOnline) patch['lastActiveAt'] = new Date();

      const result = await this.userModel
        .updateOne({ _id: id, role: UserRole.Worker }, patch)
        .exec();
      if (result.matchedCount === 0) throw new NotFoundException(`Worker ${id} not found`);
    } catch (err) {
      this.logger.error(`UsersService.updateWorkerStatus(${id}) failed`, err);
      throw err;
    }
  }

  async updateWorkerLocation(
    id: string,
    latitude: number,
    longitude: number,
    cellId?: string,
    wilayaCode?: number,
    geoHash?: string,
  ): Promise<void> {
    try {
      const patch: Partial<Record<string, unknown>> = {
        latitude,
        longitude,
        lastUpdated: new Date(),
      };
      if (cellId     != null) { patch['cellId'] = cellId; patch['lastCellUpdate'] = new Date(); }
      if (wilayaCode != null) patch['wilayaCode'] = wilayaCode;
      if (geoHash    != null) patch['geoHash']    = geoHash;

      const result = await this.userModel
        .updateOne({ _id: id, role: UserRole.Worker }, patch)
        .exec();
      if (result.matchedCount === 0) throw new NotFoundException(`Worker ${id} not found`);
    } catch (err) {
      this.logger.error(`UsersService.updateWorkerLocation(${id}) failed`, err);
      throw err;
    }
  }

  async updateWorkerFcmToken(id: string, fcmToken: string): Promise<void> {
    try {
      const result = await this.userModel
        .updateOne({ _id: id, role: UserRole.Worker }, { fcmToken, lastUpdated: new Date() })
        .exec();
      if (result.matchedCount === 0) throw new NotFoundException(`Worker ${id} not found`);
    } catch (err) {
      this.logger.error(`UsersService.updateWorkerFcmToken(${id}) failed`, err);
      throw err;
    }
  }

  async applyRating(id: string, stars: number): Promise<void> {
    try {
      const worker = await this.userModel
        .findOne({ _id: id, role: UserRole.Worker })
        .select('ratingCount ratingSum averageRating')
        .exec();

      if (!worker) throw new NotFoundException(`Worker ${id} not found`);

      const oldCount = worker.ratingCount ?? 0;
      const oldSum   = worker.ratingSum   ?? (worker.averageRating * oldCount);
      const newCount = oldCount + 1;
      const newSum   = oldSum + stars;

      const C = 3.5;
      const m = 10;
      const bayesianAvg = (m * C + newSum) / (m + newCount);

      await this.userModel.updateOne(
        { _id: id, role: UserRole.Worker },
        {
          averageRating: bayesianAvg,
          ratingCount:   newCount,
          ratingSum:     newSum,
          lastUpdated:   new Date(),
        },
      ).exec();
    } catch (err) {
      this.logger.error(`UsersService.applyRating(${id}) failed`, err);
      throw err;
    }
  }

  async getWorkerForGateway(
    uid: string,
  ): Promise<Pick<UserDocument, 'wilayaCode' | 'profession' | 'isOnline'> | null> {
    return this.userModel
      .findOne({ _id: uid, role: UserRole.Worker })
      .select('wilayaCode profession isOnline')
      .lean()
      .exec() as any;
  }
}
