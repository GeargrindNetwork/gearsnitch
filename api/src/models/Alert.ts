import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IAlert extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  deviceId: Types.ObjectId;
  type:
    | 'disconnect_warning'
    | 'panic_alarm'
    | 'reconnect_found'
    | 'gym_entry_activate'
    | 'gym_exit_deactivate';
  severity: 'low' | 'medium' | 'high' | 'critical';
  status: 'open' | 'acknowledged' | 'resolved';
  triggeredAt: Date;
  resolvedAt: Date | null;
  metadata?: Record<string, unknown>;
  createdAt: Date;
  updatedAt: Date;
}

const AlertSchema = new Schema<IAlert>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    deviceId: { type: Schema.Types.ObjectId, ref: 'Device', required: true },
    type: {
      type: String,
      enum: [
        'disconnect_warning',
        'panic_alarm',
        'reconnect_found',
        'gym_entry_activate',
        'gym_exit_deactivate',
      ],
      required: true,
    },
    severity: {
      type: String,
      enum: ['low', 'medium', 'high', 'critical'],
      required: true,
    },
    status: {
      type: String,
      enum: ['open', 'acknowledged', 'resolved'],
      default: 'open',
    },
    triggeredAt: { type: Date, required: true },
    resolvedAt: { type: Date, default: null },
    metadata: { type: Schema.Types.Mixed },
  },
  { timestamps: true }
);

AlertSchema.index({ userId: 1, status: 1 });
AlertSchema.index({ deviceId: 1, triggeredAt: -1 });

export const Alert = mongoose.model<IAlert>('Alert', AlertSchema);
