import {
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { Worker, WorkerDocument } from '../../schemas/worker.schema';
import { CreateWorkerDto } from '../../dto/create-worker.dto';
import { UpdateWorkerDto } from '../../dto/update-worker.dto';

export interface WorkerFilters {
  wilayaCode?: number;
  profession?: string;
  isOnline?: boolean;
  cellId?: string;
  limit?: number;
}

@Injectable()
export class WorkersService {
  private readonly logger = new Logger(WorkersService.name);

  constructor(
    @InjectModel(Worker.name) private readonly workerModel: Model<WorkerDocument>,
  ) {}

  async upsert(dto: CreateWorkerDto): Promise<WorkerDocument> {
    try {
      const doc = await this.workerModel
        .findByIdAndUpdate(
          dto.id,
          {
            name: dto.name,
            email: dto.email,
            phoneNumber: dto.phoneNumber ?? '',
            profession: dto.profession,
            isOnline: dto.isOnline ?? false,
            latitude: dto.latitude ?? null,
            longitude: dto.longitude ?? null,
            profileImageUrl: dto.profileImageUrl ?? null,
            fcmToken: dto.fcmToken ?? null,
            lastUpdated: new Date(),
          },
          { upsert: true, new: true, runValidators: true },
        )
        .exec();
      if (!doc) throw new NotFoundException(`Worker ${dto.id} not found after upsert`);
      return doc;
    } catch (err) {
      this.logger.error('WorkersService.upsert failed', err);
      throw err;
    }
  }

  async findById(id: string): Promise<WorkerDocument> {
    try {
      const doc = await this.workerModel.findById(id).exec();
      if (!doc) throw new NotFoundException(`Worker ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`WorkersService.findById(${id}) failed`, err);
      throw err;
    }
  }

  async findByIdOrNull(id: string): Promise<WorkerDocument | null> {
    try {
      return await this.workerModel.findById(id).exec();
    } catch (err) {
      this.logger.error(`WorkersService.findByIdOrNull(${id}) failed`, err);
      throw err;
    }
  }

  async findMany(filters: WorkerFilters): Promise<WorkerDocument[]> {
    try {
      const query: Partial<Record<string, unknown>> = {};
      if (filters.wilayaCode !== undefined) query['wilayaCode'] = filters.wilayaCode;
      if (filters.profession)               query['profession']  = filters.profession;
      if (filters.isOnline !== undefined)   query['isOnline']    = filters.isOnline;
      if (filters.cellId)                   query['cellId']      = filters.cellId;

      const limit = Math.min(filters.limit ?? 100, 200);
      return await this.workerModel.find(query).limit(limit).exec();
    } catch (err) {
      this.logger.error('WorkersService.findMany failed', err);
      throw err;
    }
  }

  async update(id: string, dto: UpdateWorkerDto): Promise<WorkerDocument> {
    try {
      const patch: Partial<Record<string, unknown>> = { lastUpdated: new Date() };
      if (dto.name !== undefined)           patch['name']           = dto.name;
      if (dto.phoneNumber !== undefined)    patch['phoneNumber']    = dto.phoneNumber;
      if (dto.profileImageUrl !== undefined) patch['profileImageUrl'] = dto.profileImageUrl;
      if (dto.cellId !== undefined)         patch['cellId']         = dto.cellId;
      if (dto.wilayaCode !== undefined)     patch['wilayaCode']     = dto.wilayaCode;
      if (dto.geoHash !== undefined)        patch['geoHash']        = dto.geoHash;
      if (dto.averageRating !== undefined)  patch['averageRating']  = dto.averageRating;
      if (dto.ratingCount !== undefined)    patch['ratingCount']    = dto.ratingCount;
      if (dto.jobsCompleted !== undefined)  patch['jobsCompleted']  = dto.jobsCompleted;
      if (dto.responseRate !== undefined)   patch['responseRate']   = dto.responseRate;
      if (dto.lastActiveAt !== undefined)   patch['lastActiveAt']   = dto.lastActiveAt;

      const doc = await this.workerModel
        .findByIdAndUpdate(id, patch, { new: true, runValidators: true })
        .exec();
      if (!doc) throw new NotFoundException(`Worker ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`WorkersService.update(${id}) failed`, err);
      throw err;
    }
  }

  async updateStatus(id: string, isOnline: boolean): Promise<void> {
    try {
      const patch: Partial<Record<string, unknown>> = {
        isOnline,
        lastUpdated: new Date(),
      };
      // Stamp lastActiveAt when going offline so recency ranking is accurate
      if (!isOnline) patch['lastActiveAt'] = new Date();

      const result = await this.workerModel.updateOne({ _id: id }, patch).exec();
      if (result.matchedCount === 0) throw new NotFoundException(`Worker ${id} not found`);
    } catch (err) {
      this.logger.error(`WorkersService.updateStatus(${id}) failed`, err);
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
      if (cellId !== undefined)     patch['cellId']       = cellId;
      if (wilayaCode !== undefined) patch['wilayaCode']   = wilayaCode;
      if (geoHash !== undefined)    patch['geoHash']      = geoHash;
      if (cellId !== undefined)     patch['lastCellUpdate'] = new Date();

      const result = await this.workerModel.updateOne({ _id: id }, patch).exec();
      if (result.matchedCount === 0) throw new NotFoundException(`Worker ${id} not found`);
    } catch (err) {
      this.logger.error(`WorkersService.updateLocation(${id}) failed`, err);
      throw err;
    }
  }

  async updateFcmToken(id: string, fcmToken: string): Promise<void> {
    try {
      const result = await this.workerModel
        .updateOne({ _id: id }, { fcmToken, lastUpdated: new Date() })
        .exec();
      if (result.matchedCount === 0) throw new NotFoundException(`Worker ${id} not found`);
    } catch (err) {
      this.logger.error(`WorkersService.updateFcmToken(${id}) failed`, err);
      throw err;
    }
  }

  /**
   * Apply Bayesian average rating update when a new review comes in.
   * Formula: (m × C + newSum) / (m + newCount)
   *   C = 3.5 (global average), m = 10 (confidence weight)
   */
  async applyRating(id: string, stars: number): Promise<void> {
    try {
      const worker = await this.workerModel.findById(id).select('ratingCount ratingSum').exec();
      if (!worker) throw new NotFoundException(`Worker ${id} not found`);

      const oldCount = worker.ratingCount ?? 0;
      const oldSum   = (worker as WorkerDocument & { ratingSum?: number }).ratingSum ?? (worker.averageRating * oldCount);
      const newCount = oldCount + 1;
      const newSum   = oldSum + stars;

      const C = 3.5;
      const m = 10;
      const bayesianAvg = (m * C + newSum) / (m + newCount);

      await this.workerModel.updateOne(
        { _id: id },
        {
          averageRating: bayesianAvg,
          ratingCount:   newCount,
          ratingSum:     newSum,
          lastUpdated:   new Date(),
        },
      ).exec();
    } catch (err) {
      this.logger.error(`WorkersService.applyRating(${id}) failed`, err);
      throw err;
    }
  }
}
