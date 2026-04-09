import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IDeviceShare extends Document {
  _id: Types.ObjectId;
  deviceId: Types.ObjectId;
  ownerUserId: Types.ObjectId;
  sharedWithUserId: Types.ObjectId;
  canReceiveAlerts: boolean;
  createdAt: Date;
}

const DeviceShareSchema = new Schema<IDeviceShare>(
  {
    deviceId: { type: Schema.Types.ObjectId, ref: 'Device', required: true },
    ownerUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    sharedWithUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    canReceiveAlerts: { type: Boolean, default: true },
  },
  { timestamps: { createdAt: true, updatedAt: false } }
);

DeviceShareSchema.index({ deviceId: 1, sharedWithUserId: 1 }, { unique: true });
DeviceShareSchema.index({ sharedWithUserId: 1 });

export const DeviceShare = mongoose.model<IDeviceShare>(
  'DeviceShare',
  DeviceShareSchema
);
