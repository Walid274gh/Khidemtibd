import { Module } from '@nestjs/common';
import { AuthModule }                from '../auth/auth.module';
import { UsersModule }               from '../users/users.module';
import { ServiceRequestsService }    from './service-requests.service';
import { ServiceRequestsController } from './service-requests.controller';

@Module({
  imports: [AuthModule, UsersModule],   // ← UsersModule replaces WorkersModule
  controllers: [ServiceRequestsController],
  providers:   [ServiceRequestsService],
  exports:     [ServiceRequestsService],
})
export class ServiceRequestsModule {}
