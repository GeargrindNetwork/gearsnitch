import mongoose, { Schema, Document, Types } from 'mongoose';

export interface ISession extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  jti: string;
  deviceName: string;
  platform: 'ios' | 'watchos' | 'web';
  ipAddress: string;
  userAgent: string;
  expiresAt: Date;
  revokedAt: Date | null;
  createdAt: Date;
}

const SessionSchema = new Schema<ISession>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    jti: { type: String, required: true },
    deviceName: { type: String, required: true },
    platform: { type: String, enum: ['ios', 'watchos', 'web'], required: true },
    ipAddress: { type: String, required: true },
    userAgent: { type: String, required: true },
    expiresAt: { type: Date, required: true },
    revokedAt: { type: Date, default: null },
  },
  { timestamps: { createdAt: true, updatedAt: false } }
);

SessionSchema.index({ jti: 1 }, { unique: true });
SessionSchema.index({ userId: 1, expiresAt: 1 });

export const Session = mongoose.model<ISession>('Session', SessionSchema);
