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
import { WorkerBid, WorkerBidDocument }         from '../../schemas/worker-bid.schema';
import { ServiceRequest, ServiceRequestDocument } from '../../schemas/service-request.schema';
import { CreateBidDto }    from '../../dto/create-bid.dto';
import { BidStatus, ServiceStatus } from '../../common/enums';

export interface BidFilters {
  serviceRequestId?: string;
  workerId?: string;
  status?: string;
  limit?: number;
}

@Injectable()
export class BidsService {
  private readonly logger = new Logger(BidsService.name);

  constructor(
    @InjectModel(WorkerBid.name)
    private readonly bidModel: Model<WorkerBidDocument>,
    @InjectModel(ServiceRequest.name)
    private readonly requestModel: Model<ServiceRequestDocument>,
  ) {}

  async submit(dto: CreateBidDto, uid: string): Promise<WorkerBidDocument> {
    try {
      if (dto.workerId !== uid) throw new ForbiddenException('workerId must match authenticated user');

      const request = await this.requestModel.findById(dto.serviceRequestId).exec();
      if (!request) throw new NotFoundException(`Service request ${dto.serviceRequestId} not found`);
      if (
        request.status !== ServiceStatus.Open &&
        request.status !== ServiceStatus.AwaitingSelection
      ) {
        throw new BadRequestException(`Request is not accepting bids (status: ${request.status})`);
      }

      if (request.userId === uid) throw new ForbiddenException('You cannot bid on your own service request');

      const existingBid = await this.bidModel
        .findOne({ serviceRequestId: dto.serviceRequestId, workerId: uid, status: BidStatus.Pending })
        .exec();
      if (existingBid) throw new BadRequestException('You already have a pending bid on this request');

      const bid = new this.bidModel({
        _id: uuidv4(),
        ...dto,
        status:    BidStatus.Pending,
        createdAt: new Date(),
      });
      const saved = await bid.save();

      await this.requestModel.updateOne(
        { _id: dto.serviceRequestId },
        { $inc: { bidCount: 1 }, status: ServiceStatus.AwaitingSelection },
      ).exec();

      return saved;
    } catch (err) {
      this.logger.error('BidsService.submit failed', err);
      throw err;
    }
  }

  async findById(id: string): Promise<WorkerBidDocument> {
    try {
      const doc = await this.bidModel.findById(id).exec();
      if (!doc) throw new NotFoundException(`Bid ${id} not found`);
      return doc;
    } catch (err) {
      this.logger.error(`BidsService.findById(${id}) failed`, err);
      throw err;
    }
  }

  async findMany(filters: BidFilters): Promise<WorkerBidDocument[]> {
    try {
      const query: Partial<Record<string, unknown>> = {};
      if (filters.serviceRequestId) query['serviceRequestId'] = filters.serviceRequestId;
      if (filters.workerId)         query['workerId']         = filters.workerId;
      if (filters.status)           query['status']           = filters.status;

      return this.bidModel
        .find(query)
        .sort({ createdAt: 1 })
        .limit(Math.min(filters.limit ?? 50, 100))
        .exec();
    } catch (err) {
      this.logger.error('BidsService.findMany failed', err);
      throw err;
    }
  }

  async accept(bidId: string, uid: string): Promise<void> {
    try {
      const bid = await this.bidModel.findById(bidId).exec();
      if (!bid) throw new NotFoundException(`Bid ${bidId} not found`);
      if (bid.status !== BidStatus.Pending) throw new BadRequestException(`Bid is not pending (status: ${bid.status})`);

      const request = await this.requestModel.findById(bid.serviceRequestId).exec();
      if (!request) throw new NotFoundException(`Service request ${bid.serviceRequestId} not found`);
      if (request.userId !== uid) throw new ForbiddenException('Only the request owner can accept a bid');
      if (
        request.status !== ServiceStatus.Open &&
        request.status !== ServiceStatus.AwaitingSelection
      ) {
        throw new BadRequestException(`Cannot accept bid on request in status: ${request.status}`);
      }

      await this.bidModel.updateOne({ _id: bidId }, { status: BidStatus.Accepted, acceptedAt: new Date() }).exec();

      await this.requestModel.updateOne(
        { _id: bid.serviceRequestId },
        {
          status:        ServiceStatus.BidSelected,
          selectedBidId: bidId,
          workerId:      bid.workerId,
          workerName:    bid.workerName,
          agreedPrice:   bid.proposedPrice,
          bidSelectedAt: new Date(),
        },
      ).exec();

      await this.bidModel.updateMany(
        { serviceRequestId: bid.serviceRequestId, _id: { $ne: bidId }, status: BidStatus.Pending },
        { status: BidStatus.Declined },
      ).exec();
    } catch (err) {
      this.logger.error(`BidsService.accept(${bidId}) failed`, err);
      throw err;
    }
  }

  async withdraw(bidId: string, uid: string): Promise<void> {
    try {
      const bid = await this.bidModel.findById(bidId).exec();
      if (!bid) throw new NotFoundException(`Bid ${bidId} not found`);
      if (bid.workerId !== uid) throw new ForbiddenException('You can only withdraw your own bids');
      if (bid.status !== BidStatus.Pending) throw new BadRequestException(`Can only withdraw pending bids (status: ${bid.status})`);

      await this.bidModel.updateOne({ _id: bidId }, { status: BidStatus.Withdrawn }).exec();
      await this.requestModel.updateOne({ _id: bid.serviceRequestId }, { $inc: { bidCount: -1 } }).exec();
    } catch (err) {
      this.logger.error(`BidsService.withdraw(${bidId}) failed`, err);
      throw err;
    }
  }
}
