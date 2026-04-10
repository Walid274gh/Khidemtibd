// ══════════════════════════════════════════════════════════════════════════════
// User Schema — Unified collection for ALL users (clients & workers)
//
// DESIGN RATIONALE:
//   Every worker is a user — there is no scenario where a worker exists without
//   a user identity. Maintaining two collections (users + workers) duplicated
//   identity fields (name, email, phone, location, fcmToken, profileImageUrl)
//   and forced every service to manage two write paths, two cache entries, and
//   two transaction legs for every auth operation.
//
//   The unified design:
//     • Eliminates duplication — one document per person, always.
//     • Simplifies auth: registration, login, and profile update touch one doc.
//     • `role: 'client' | 'worker'` is the single discriminator.
//     • Worker-specific fields (profession, isOnline, rating…) default to
//       neutral values so client queries never see "online" workers and vice-versa.
//     • Partial indexes restrict heavy worker indexes to role='worker' documents,
//       keeping the index footprint proportional to the actual worker count.
//
// MIGRATION (run once against production):
//   db.workers.find().forEach(w => {
//     w.role = 'worker';
//     db.users.updateOne({ _id: w._id }, { $set: w }, { upsert: true });
//   });
//   db.workers.drop();
// ══════════════════════════════════════════════════════════════════════════════

import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { Document } from 'mongoose';

export enum UserRole {
  Client = 'client',
  Worker = 'worker',
}

export type UserDocument = User & Document;

/**
 * Backward-compatible type alias so existing code importing WorkerDocument
 * from this module compiles without changes.
 */
export type WorkerDocument = UserDocument;

@Schema({ collection: 'users', timestamps: false, versionKey: false })
export class User {
  // ── Identity ────────────────────────────────────────────────────────────────
  @Prop({ required: true, index: true })
  _id: string;                         // Firebase UID — same for client & worker

  @Prop({ required: true })
  name: string;

  @Prop({ required: true, lowercase: true, trim: true })
  email: string;

  @Prop({ default: '' })
  phoneNumber: string;

  @Prop({
    required: true,
    enum: Object.values(UserRole),
    default: UserRole.Client,
    index: true,
  })
  role: UserRole;

  // ── Location (shared) ────────────────────────────────────────────────────────
  @Prop({ type: Number, default: null })
  latitude: number | null;

  @Prop({ type: Number, default: null })
  longitude: number | null;

  @Prop({ required: true, type: Date })
  lastUpdated: Date;

  @Prop({ type: String, default: null })
  cellId: string | null;

  @Prop({ type: Number, default: null })
  wilayaCode: number | null;

  @Prop({ type: String, default: null })
  geoHash: string | null;

  @Prop({ type: Date, default: null })
  lastCellUpdate: Date | null;

  // ── Media / push (shared) ────────────────────────────────────────────────────
  @Prop({ type: String, default: null })
  profileImageUrl: string | null;

  @Prop({ type: String, default: null })
  fcmToken: string | null;

  // ── Worker-specific ──────────────────────────────────────────────────────────
  // Defaults guarantee that client documents never satisfy worker-targeted
  // queries (e.g. { role: 'worker', isOnline: true }).

  /** Trade / profession key (null for clients). */
  @Prop({ type: String, default: null })
  profession: string | null;

  /** Online status — meaningful only for workers. Always false for clients. */
  @Prop({ default: false })
  isOnline: boolean;

  /** Bayesian average rating (0–5). */
  @Prop({ default: 0.0, min: 0, max: 5 })
  averageRating: number;

  @Prop({ default: 0, min: 0 })
  ratingCount: number;

  /** Running sum of stars — enables Bayesian recomputation without history. */
  @Prop({ default: 0, min: 0 })
  ratingSum: number;

  @Prop({ default: 0, min: 0 })
  jobsCompleted: number;

  /** Fraction of bids responded to (0–1). */
  @Prop({ default: 0.7, min: 0, max: 1 })
  responseRate: number;

  /** Timestamp of last offline transition — used for recency ranking. */
  @Prop({ type: Date, default: null })
  lastActiveAt: Date | null;
}

export const UserSchema = SchemaFactory.createForClass(User);

// ── Shared indexes ────────────────────────────────────────────────────────────
UserSchema.index({ email: 1 }, { unique: true });
UserSchema.index({ wilayaCode: 1 });
UserSchema.index({ geoHash: 1 });

// ── Partial indexes (role = 'worker' documents only) ──────────────────────────
// MongoDB partial indexes only maintain index entries for documents satisfying
// the partialFilterExpression. Client documents are invisible to these indexes,
// keeping storage and write amplification proportional to the worker count.
const WORKER_ONLY = { partialFilterExpression: { role: UserRole.Worker } } as const;

UserSchema.index({ isOnline: 1, wilayaCode: 1 },             WORKER_ONLY);
UserSchema.index({ isOnline: 1, profession: 1 },             WORKER_ONLY);
UserSchema.index({ wilayaCode: 1, profession: 1 },           WORKER_ONLY);
UserSchema.index({ cellId: 1, profession: 1, isOnline: 1 },  WORKER_ONLY);
UserSchema.index({ wilayaCode: 1, isOnline: 1 },             WORKER_ONLY);
