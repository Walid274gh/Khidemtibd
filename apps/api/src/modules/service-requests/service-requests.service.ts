import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { v4 as uuidv4 } from 'uuid';
import { ServiceRequest, ServiceRequestDocument } from '../../schemas/service-request.schema';
import { WorkerBid, WorkerBidDocument } from '../../schemas/worker-bid.schema';
import { CreateServiceRequestDto } from '../../dto/create-service-request.dto';
import { UpdateServiceRequestDto } from '../../dto/update-service-request.dto';
import { SubmitRatingDto } from '../../dto/submit-rating.dto';
import { ServiceStatus, ServicePriority } from '../../common/enums';
import { WorkersService } from '../workers/workers.service';

export interface ServiceRequestFilters {
  userId?: string;
  workerId?: string;
  status?: string | string[];
  wilayaCode?: number;
  serviceType?: string;
  limit?: number;
}

@Injectable()
export class ServiceRequestsService {
  private readonly logger = new Logger(ServiceRequestsService.name);

  constructor(
    @InjectModel(ServiceRequest.name)
    private readonly requestModel: Model<ServiceRequestDocument>,
    @InjectModel(WorkerBid.name)
    private readonly bidModel: Model<WorkerBidDocument>,
    private readonly workersService: WorkersService,
  ) {}

  async create(dto: CreateServiceRequestDto, uid: string): Promise<ServiceRequestDocument> {
    try {
      if (dto.userId !== uid) {
        throw new ForbiddenException('userId must match authenticated user');
      }

      const id = uuidv4();
      const request = new this.requestModel({
        _id: id,
        ...dto,
        status: ServiceStatus.Open,
        priority: dto.priority ?? ServicePriority.Normal,
        bidCount: 0,
        mediaUrls: dto.mediaUrls ?? [],
        createdAt: new Date(),
      });
      return await request.save();
    } catch (err) {
      this.logger.error('ServiceRequestsService.create failed', err);
      throw err;
    }
  }

  async findById(id: string): Promise<ServiceRequestDocument> {
    try {
      const doc = await this.requestModel.findById(id).exec();
      if (!doc) throw new NotFoundException(`Service request ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`ServiceRequestsService.findById(${id}) failed`, err);
      throw err;
    }
  }

  async findMany(filters: ServiceRequestFilters): Promise<ServiceRequestDocument[]> {
    try {
      const query: Partial<Record<string, unknown>> = {};
      if (filters.userId)    query['userId']      = filters.userId;
      if (filters.workerId)  query['workerId']    = filters.workerId;
      if (filters.wilayaCode !== undefined) query['wilayaCode'] = filters.wilayaCode;
      if (filters.serviceType) query['serviceType'] = filters.serviceType;

      if (filters.status) {
        if (Array.isArray(filters.status)) {
          query['status'] = { $in: filters.status };
        } else {
          query['status'] = filters.status;
        }
      }

      const limit = Math.min(filters.limit ?? 50, 100);
      return await this.requestModel
        .find(query)
        .sort({ createdAt: -1 })
        .limit(limit)
        .exec();
    } catch (err) {
      this.logger.error('ServiceRequestsService.findMany failed', err);
      throw err;
    }
  }

  async update(
    id: string,
    dto: UpdateServiceRequestDto,
    uid: string,
  ): Promise<ServiceRequestDocument> {
    try {
      const existing = await this.requestModel.findById(id).exec();
      if (!existing) throw new NotFoundException(`Service request ${id} not found`);
      if (existing.userId !== uid) {
        throw new ForbiddenException('You can only update your own requests');
      }

      const doc = await this.requestModel
        .findByIdAndUpdate(id, dto, { new: true, runValidators: true })
        .exec();
      if (!doc) throw new NotFoundException(`Service request ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`ServiceRequestsService.update(${id}) failed`, err);
      throw err;
    }
  }

  async cancel(id: string, uid: string): Promise<void> {
    try {
      const request = await this.requestModel.findById(id).exec();
      if (!request) throw new NotFoundException(`Service request ${id} not found`);
      if (request.userId !== uid) {
        throw new ForbiddenException('You can only cancel your own requests');
      }
      if (request.status === ServiceStatus.Completed || request.status === ServiceStatus.Cancelled) {
        throw new BadRequestException(`Cannot cancel a request in status: ${request.status}`);
      }

      await this.requestModel.updateOne({ _id: id }, { status: ServiceStatus.Cancelled }).exec();

      // Best-effort: decline all pending bids for this request
      await this.bidModel
        .updateMany(
          { serviceRequestId: id, status: 'pending' },
          { status: 'declined' },
        )
        .exec();
    } catch (err) {
      this.logger.error(`ServiceRequestsService.cancel(${id}) failed`, err);
      throw err;
    }
  }

  async startJob(id: string, uid: string): Promise<void> {
    try {
      const request = await this.requestModel.findById(id).exec();
      if (!request) throw new NotFoundException(`Service request ${id} not found`);
      if (request.workerId !== uid) {
        throw new ForbiddenException('Only the assigned worker can start this job');
      }
      if (request.status !== ServiceStatus.BidSelected) {
        throw new BadRequestException(`Cannot start job in status: ${request.status}`);
      }

      await this.requestModel
        .updateOne({ _id: id }, { status: ServiceStatus.InProgress, acceptedAt: new Date() })
        .exec();
    } catch (err) {
      this.logger.error(`ServiceRequestsService.startJob(${id}) failed`, err);
      throw err;
    }
  }

  async completeJob(
    id: string,
    uid: string,
    workerNotes?: string,
    finalPrice?: number,
  ): Promise<void> {
    try {
      const request = await this.requestModel.findById(id).exec();
      if (!request) throw new NotFoundException(`Service request ${id} not found`);
      if (request.workerId !== uid) {
        throw new ForbiddenException('Only the assigned worker can complete this job');
      }
      if (
        request.status !== ServiceStatus.BidSelected &&
        request.status !== ServiceStatus.InProgress
      ) {
        throw new BadRequestException(`Cannot complete job in status: ${request.status}`);
      }

      const patch: Partial<Record<string, unknown>> = {
        status: ServiceStatus.Completed,
        completedAt: new Date(),
      };
      if (workerNotes) patch['workerNotes'] = workerNotes;
      if (finalPrice !== undefined) patch['finalPrice'] = finalPrice;

      await this.requestModel.updateOne({ _id: id }, patch).exec();
    } catch (err) {
      this.logger.error(`ServiceRequestsService.completeJob(${id}) failed`, err);
      throw err;
    }
  }

  async submitRating(id: string, uid: string, dto: SubmitRatingDto): Promise<void> {
    try {
      const request = await this.requestModel.findById(id).exec();
      if (!request) throw new NotFoundException(`Service request ${id} not found`);
      if (request.userId !== uid) {
        throw new ForbiddenException('Only the client can rate this request');
      }
      if (request.status !== ServiceStatus.Completed) {
        throw new BadRequestException('Can only rate completed jobs');
      }
      if (request.clientRating !== null && request.clientRating !== undefined) {
        throw new BadRequestException('This request has already been rated');
      }

      const patch: Partial<Record<string, unknown>> = { clientRating: dto.stars };
      if (dto.comment) patch['reviewComment'] = dto.comment;

      await this.requestModel.updateOne({ _id: id }, patch).exec();

      // Update worker's Bayesian average rating
      if (request.workerId) {
        await this.workersService.applyRating(request.workerId, dto.stars);
      }
    } catch (err) {
      this.logger.error(`ServiceRequestsService.submitRating(${id}) failed`, err);
      throw err;
    }
  }
}
