import mongoose, { Schema, Document, Types } from 'mongoose';

export interface INotificationToken extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  platform: 'ios' | 'watchos';
  token: string;
  environment: 'sandbox' | 'production';
  active: boolean;
  lastUsedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

const NotificationTokenSchema = new Schema<INotificationToken>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    platform: { type: String, enum: ['ios', 'watchos'], required: true },
    token: { type: String, required: true },
    environment: {
      type: String,
      enum: ['sandbox', 'production'],
      required: true,
    },
    active: { type: Boolean, default: true },
    lastUsedAt: { type: Date },
  },
  { timestamps: true }
);

NotificationTokenSchema.index({ token: 1 }, { unique: true });
NotificationTokenSchema.index({ userId: 1 });

export const NotificationToken = mongoose.model<INotificationToken>(
  'NotificationToken',
  NotificationTokenSchema
);
