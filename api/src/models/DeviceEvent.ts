import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IDeviceEvent extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  deviceId: Types.ObjectId;
  action: 'connect' | 'disconnect';
  occurredAt: Date;
  location?: {
    type: 'Point';
    coordinates: [number, number];
  };
  signalStrength?: number | null;
  source: 'ios' | 'web' | 'system';
  metadata?: unknown;
  createdAt: Date;
  updatedAt: Date;
}

const DeviceEventLocationSchema = new Schema(
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
        message: 'Device event coordinates must contain longitude and latitude.',
      },
    },
  },
  {
    _id: false,
    id: false,
  },
);

const DeviceEventSchema = new Schema<IDeviceEvent>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    deviceId: { type: Schema.Types.ObjectId, ref: 'Device', required: true },
    action: {
      type: String,
      enum: ['connect', 'disconnect'],
      required: true,
    },
    occurredAt: { type: Date, required: true, default: Date.now },
    location: {
      type: DeviceEventLocationSchema,
      default: undefined,
    },
    signalStrength: { type: Number, default: null },
    source: {
      type: String,
      enum: ['ios', 'web', 'system'],
      default: 'ios',
    },
    metadata: { type: Schema.Types.Mixed, default: undefined },
  },
  { timestamps: true }
);

DeviceEventSchema.index({ userId: 1, deviceId: 1, occurredAt: -1 });
DeviceEventSchema.index({ userId: 1, occurredAt: -1 });
DeviceEventSchema.index({ deviceId: 1, action: 1, occurredAt: -1 });
DeviceEventSchema.index({ location: '2dsphere' });

export const DeviceEvent = mongoose.model<IDeviceEvent>('DeviceEvent', DeviceEventSchema);
