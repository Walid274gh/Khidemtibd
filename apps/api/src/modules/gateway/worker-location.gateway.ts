import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  MessageBody,
  ConnectedSocket,
  OnGatewayConnection,
  OnGatewayDisconnect,
  WsException,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import * as admin from 'firebase-admin';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { Worker, WorkerDocument } from '../../schemas/worker.schema';

interface AuthenticatedSocket extends Socket {
  data: { uid: string; isWorker: boolean; wilayaCode?: number };
}

interface LocationPayload {
  lat: number;
  lng: number;
}

interface StatusPayload {
  isOnline: boolean;
}

@WebSocketGateway({
  namespace: '/workers',
  cors: { origin: '*', credentials: false },
  transports: ['websocket', 'polling'],
})
export class WorkerLocationGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer() private readonly server!: Server;
  private readonly logger = new Logger(WorkerLocationGateway.name);

  constructor(
    @InjectModel(Worker.name)
    private readonly workerModel: Model<WorkerDocument>,
  ) {}

  // ── Connection lifecycle ───────────────────────────────────────────────────

  async handleConnection(socket: AuthenticatedSocket): Promise<void> {
    try {
      const token =
        socket.handshake.auth?.['token'] as string | undefined ??
        (socket.handshake.headers['authorization'] as string | undefined)?.replace('Bearer ', '');

      if (!token) {
        this.logger.warn(`[WS workers] Rejected unauthenticated socket ${socket.id}`);
        socket.disconnect(true);
        return;
      }

      const decoded = await admin.auth().verifyIdToken(token);
      socket.data.uid = decoded.uid;

      // Determine if this socket belongs to a worker or a viewer
      const worker = await this.workerModel
        .findById(decoded.uid)
        .select('wilayaCode profession isOnline')
        .lean()
        .exec();

      socket.data.isWorker = !!worker;

      if (worker) {
        socket.data.wilayaCode = worker.wilayaCode ?? undefined;
        // Workers join their own room so clients can target them
        await socket.join(`worker:${decoded.uid}`);
        if (worker.wilayaCode) {
          await socket.join(`wilaya:${worker.wilayaCode}`);
        }
        this.logger.log(`[WS workers] Worker ${decoded.uid} connected (socket ${socket.id})`);
      } else {
        // Clients/viewers — rooms joined on demand via subscribe events
        this.logger.log(`[WS workers] Viewer ${decoded.uid} connected (socket ${socket.id})`);
      }
    } catch (err) {
      this.logger.warn(`[WS workers] Auth failure on socket ${socket.id}: ${err}`);
      socket.disconnect(true);
    }
  }

  handleDisconnect(socket: AuthenticatedSocket): void {
    this.logger.log(`[WS workers] Socket ${socket.id} (uid=${socket.data?.uid ?? 'unknown'}) disconnected`);
  }

  // ── Worker → Server events ─────────────────────────────────────────────────

  /**
   * Worker broadcasts their real-time GPS position.
   * Emits `worker:location` to the room `wilaya:{wilayaCode}`.
   * Also updates Mongo (fire-and-forget — stream consumers will pick it up).
   */
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

    try {
      // Persist to MongoDB (non-blocking)
      this.workerModel
        .updateOne({ _id: workerId }, { latitude: lat, longitude: lng, lastUpdated: new Date() })
        .exec()
        .catch((e: unknown) => this.logger.error('Location persist failed', e));

      // Broadcast to all viewers in this wilaya
      const event = { workerId, lat, lng, ts: Date.now() };
      if (socket.data.wilayaCode) {
        this.server.to(`wilaya:${socket.data.wilayaCode}`).emit('worker:location', event);
      }
      // Also broadcast to anyone watching this worker specifically
      this.server.to(`worker:${workerId}`).emit('worker:location', event);
    } catch (err) {
      this.logger.error(`handleUpdateLocation(${workerId})`, err);
    }
  }

  /**
   * Worker toggles their online/offline status.
   * Emits `worker:status` to the room `wilaya:{wilayaCode}`.
   */
  @SubscribeMessage('worker:set_status')
  async handleSetStatus(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: StatusPayload,
  ): Promise<void> {
    if (!socket.data?.isWorker) return;

    const { isOnline } = payload;
    if (typeof isOnline !== 'boolean') return;

    const workerId = socket.data.uid;

    try {
      await this.workerModel
        .updateOne(
          { _id: workerId },
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
    } catch (err) {
      this.logger.error(`handleSetStatus(${workerId})`, err);
    }
  }

  // ── Client → Server: room subscriptions ───────────────────────────────────

  /**
   * Viewer joins `wilaya:{wilayaCode}` to receive all worker location events.
   */
  @SubscribeMessage('subscribe:wilaya')
  async handleSubscribeWilaya(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { wilayaCode: number },
  ): Promise<void> {
    if (!payload?.wilayaCode || typeof payload.wilayaCode !== 'number') return;
    await socket.join(`wilaya:${payload.wilayaCode}`);
  }

  /**
   * Viewer joins `worker:{workerId}` to receive a single worker's events.
   */
  @SubscribeMessage('subscribe:worker')
  async handleSubscribeWorker(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { workerId: string },
  ): Promise<void> {
    if (!payload?.workerId || typeof payload.workerId !== 'string') return;
    await socket.join(`worker:${payload.workerId}`);
  }

  // ── Server-initiated helpers (called by other services) ───────────────────

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
