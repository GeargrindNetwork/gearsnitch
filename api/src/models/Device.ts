import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IDevice extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  name: string;
  nickname?: string | null;
  type: 'earbuds' | 'tracker' | 'belt' | 'bag' | 'other';
  identifier: string;
  hardwareModel?: string;
  firmwareVersion?: string;
  status:
    | 'registered'
    | 'active'
    | 'inactive'
    | 'connected'
    | 'monitoring'
    | 'disconnected'
    | 'lost'
    | 'reconnected';
  isFavorite: boolean;
  monitoringEnabled: boolean;
  lastSeenAt: Date | null;
  lastSeenLocation?: {
    type: 'Point';
    coordinates: [number, number];
  };
  lastSignalStrength?: number;
  createdAt: Date;
  updatedAt: Date;
}

const DeviceSchema = new Schema<IDevice>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    name: { type: String, required: true },
    nickname: { type: String, default: null },
    type: {
      type: String,
      enum: ['earbuds', 'tracker', 'belt', 'bag', 'other'],
      required: true,
    },
    identifier: { type: String, required: true },
    hardwareModel: { type: String },
    firmwareVersion: { type: String },
    status: {
      type: String,
      enum: [
        'registered',
        'active',
        'inactive',
        'connected',
        'monitoring',
        'disconnected',
        'lost',
        'reconnected',
      ],
      default: 'registered',
    },
    isFavorite: { type: Boolean, default: false },
    monitoringEnabled: { type: Boolean, default: true },
    lastSeenAt: { type: Date, default: null },
    lastSeenLocation: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number] },
    },
    lastSignalStrength: { type: Number },
  },
  { timestamps: true }
);

DeviceSchema.index({ userId: 1 });
DeviceSchema.index({ status: 1 });
DeviceSchema.index({ userId: 1, identifier: 1 });
DeviceSchema.index({ userId: 1, isFavorite: -1, updatedAt: -1 });
DeviceSchema.index({ lastSeenLocation: '2dsphere' });

export const Device = mongoose.model<IDevice>('Device', DeviceSchema);
