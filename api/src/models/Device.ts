import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IDevice extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  name: string;
  nickname?: string | null;
  type: 'earbuds' | 'tracker' | 'belt' | 'bag' | 'watch' | 'other';
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
  // BLE Battery Service (0x180F) telemetry. Written by
  // `PATCH /devices/:id/battery` from the iOS `BatteryLevelReader`
  // (backlog item #17). `lastBatteryLevel` is a 0–100 percentage,
  // `lastBatteryReadAt` the time the reading arrived at the server, and
  // `lastLowBatteryNotifiedAt` marks the last time we enqueued a
  // low-battery push so we can apply a 12h per-device cooldown.
  lastBatteryLevel?: number | null;
  lastBatteryReadAt?: Date | null;
  lastLowBatteryNotifiedAt?: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

const DeviceLocationSchema = new Schema(
  {
    type: {
      type: String,
      enum: ['Point'],
      required: function requiresGeoType(this: { coordinates?: unknown[] }) {
        return Array.isArray(this.coordinates) && this.coordinates.length === 2;
      },
    },
    coordinates: {
      type: [Number],
      validate: {
        validator: (value: unknown) => value == null || (Array.isArray(value) && value.length === 2),
        message: 'Device lastSeenLocation coordinates must contain longitude and latitude.',
      },
    },
  },
  {
    _id: false,
    id: false,
  }
);

const DeviceSchema = new Schema<IDevice>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    name: { type: String, required: true },
    nickname: { type: String, default: null },
    type: {
      type: String,
      enum: ['earbuds', 'tracker', 'belt', 'bag', 'watch', 'other'],
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
      type: DeviceLocationSchema,
      default: undefined,
    },
    lastSignalStrength: { type: Number },
    lastBatteryLevel: {
      type: Number,
      default: null,
      min: 0,
      max: 100,
    },
    lastBatteryReadAt: { type: Date, default: null },
    lastLowBatteryNotifiedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

DeviceSchema.index({ userId: 1 });
DeviceSchema.index({ status: 1 });
DeviceSchema.index({ userId: 1, identifier: 1 });
DeviceSchema.index({ userId: 1, isFavorite: -1, updatedAt: -1 });
DeviceSchema.index({ lastSeenLocation: '2dsphere' });

export const Device = mongoose.model<IDevice>('Device', DeviceSchema);
