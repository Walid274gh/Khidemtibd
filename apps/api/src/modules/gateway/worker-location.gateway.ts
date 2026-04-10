import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  MessageBody,
  ConnectedSocket,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import * as admin from 'firebase-admin';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { User, UserDocument, UserRole } from '../../schemas/user.schema';

interface AuthenticatedSocket extends Socket {
  data: { uid: string; isWorker: boolean; wilayaCode?: number };
}

interface LocationPayload { lat: number; lng: number; }
interface StatusPayload   { isOnline: boolean; }

@WebSocketGateway({
  namespace: '/workers',
  cors: { origin: '*', credentials: false },
  transports: ['websocket', 'polling'],
})
export class WorkerLocationGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer() private readonly server!: Server;
  private readonly logger = new Logger(WorkerLocationGateway.name);

  constructor(
    @InjectModel(User.name)
    private readonly userModel: Model<UserDocument>,   // ← unified collection
  ) {}

  // ── Connection lifecycle ────────────────────────────────────────────────────

  async handleConnection(socket: AuthenticatedSocket): Promise<void> {
    try {
      const token =
        socket.handshake.auth?.['token'] as string | undefined ??
        (socket.handshake.headers['authorization'] as string | undefined)?.replace('Bearer ', '');

      if (!token) { socket.disconnect(true); return; }

      const decoded = await admin.auth().verifyIdToken(token);
      socket.data.uid = decoded.uid;

      // ↓ Query the unified users collection — worker check via role field
      const user = await this.userModel
        .findOne({ _id: decoded.uid, role: UserRole.Worker })
        .select('wilayaCode profession isOnline')
        .lean()
        .exec();

      socket.data.isWorker = !!user;

      if (user) {
        socket.data.wilayaCode = (user as any).wilayaCode ?? undefined;
        await socket.join(`worker:${decoded.uid}`);
        if ((user as any).wilayaCode) {
          await socket.join(`wilaya:${(user as any).wilayaCode}`);
        }
        this.logger.log(`[WS workers] Worker ${decoded.uid} connected (${socket.id})`);
      } else {
        this.logger.log(`[WS workers] Viewer ${decoded.uid} connected (${socket.id})`);
      }
    } catch (err) {
      this.logger.warn(`[WS workers] Auth failure on socket ${socket.id}: ${err}`);
      socket.disconnect(true);
    }
  }

  handleDisconnect(socket: AuthenticatedSocket): void {
    this.logger.log(`[WS workers] Socket ${socket.id} (uid=${socket.data?.uid ?? 'unknown'}) disconnected`);
  }

  // ── Worker → Server events ──────────────────────────────────────────────────

  @SubscribeMessage('worker:update_location')
  async handleUpdateLocation(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: LocationPayload,
  ): Promise<void> {
    if (!socket.data?.isWorker) return;
    const { lat, lng } = payload;
    if (typeof lat !== 'number' || typeof lng !== 'number') return;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return;

    const workerId = socket.data.uid;

    // Persist to unified users collection
    this.userModel
      .updateOne(
        { _id: workerId, role: UserRole.Worker },
        { latitude: lat, longitude: lng, lastUpdated: new Date() },
      )
      .exec()
      .catch((e: unknown) => this.logger.error('Location persist failed', e));

    const event = { workerId, lat, lng, ts: Date.now() };
    if (socket.data.wilayaCode) {
      this.server.to(`wilaya:${socket.data.wilayaCode}`).emit('worker:location', event);
    }
    this.server.to(`worker:${workerId}`).emit('worker:location', event);
  }

  @SubscribeMessage('worker:set_status')
  async handleSetStatus(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: StatusPayload,
  ): Promise<void> {
    if (!socket.data?.isWorker) return;
    const { isOnline } = payload;
    if (typeof isOnline !== 'boolean') return;

    const workerId = socket.data.uid;

    await this.userModel
      .updateOne(
        { _id: workerId, role: UserRole.Worker },
        {
          isOnline,
          lastUpdated: new Date(),
          ...(isOnline ? {} : { lastActiveAt: new Date() }),
        },
      )
      .exec();

    const event = { workerId, isOnline, ts: Date.now() };
    if (socket.data.wilayaCode) {
      this.server.to(`wilaya:${socket.data.wilayaCode}`).emit('worker:status', event);
    }
    this.server.to(`worker:${workerId}`).emit('worker:status', event);
  }

  // ── Client → Server: room subscriptions ────────────────────────────────────

  @SubscribeMessage('subscribe:wilaya')
  async handleSubscribeWilaya(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { wilayaCode: number },
  ): Promise<void> {
    if (!payload?.wilayaCode || typeof payload.wilayaCode !== 'number') return;
    await socket.join(`wilaya:${payload.wilayaCode}`);
  }

  @SubscribeMessage('subscribe:worker')
  async handleSubscribeWorker(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { workerId: string },
  ): Promise<void> {
    if (!payload?.workerId || typeof payload.workerId !== 'string') return;
    await socket.join(`worker:${payload.workerId}`);
  }

  // ── Server-initiated helpers ─────────────────────────────────────────────────

  emitWorkerLocation(workerId: string, lat: number, lng: number, wilayaCode?: number): void {
    const event = { workerId, lat, lng, ts: Date.now() };
    if (wilayaCode) this.server.to(`wilaya:${wilayaCode}`).emit('worker:location', event);
    this.server.to(`worker:${workerId}`).emit('worker:location', event);
  }

  emitWorkerStatus(workerId: string, isOnline: boolean, wilayaCode?: number): void {
    const event = { workerId, isOnline, ts: Date.now() };
    if (wilayaCode) this.server.to(`wilaya:${wilayaCode}`).emit('worker:status', event);
    this.server.to(`worker:${workerId}`).emit('worker:status', event);
  }
}
