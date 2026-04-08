import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { Worker, WorkerSchema } from '../../schemas/worker.schema';
import { WorkerLocationGateway } from './worker-location.gateway';
import { ServiceRequestGateway } from './service-request.gateway';
import { BidsGateway } from './bids.gateway';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: Worker.name, schema: WorkerSchema }]),
  ],
  providers: [WorkerLocationGateway, ServiceRequestGateway, BidsGateway],
  exports: [WorkerLocationGateway, ServiceRequestGateway, BidsGateway],
})
export class GatewayModule {}
