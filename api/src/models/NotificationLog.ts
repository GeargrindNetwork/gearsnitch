import mongoose, { Schema, Document, Types } from 'mongoose';

export interface INotificationLog extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  tokenId: Types.ObjectId;
  notificationType: string;
  sentAt: Date;
  deliveredAt: Date | null;
  openedAt: Date | null;
  failureReason: string | null;
  createdAt: Date;
}

const NotificationLogSchema = new Schema<INotificationLog>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    tokenId: {
      type: Schema.Types.ObjectId,
      ref: 'NotificationToken',
      required: true,
    },
    notificationType: { type: String, required: true },
    sentAt: { type: Date, required: true },
    deliveredAt: { type: Date, default: null },
    openedAt: { type: Date, default: null },
    failureReason: { type: String, default: null },
  },
  { timestamps: { createdAt: true, updatedAt: false } }
);

NotificationLogSchema.index({ userId: 1, sentAt: -1 });
NotificationLogSchema.index({ notificationType: 1 });

export const NotificationLog = mongoose.model<INotificationLog>(
  'NotificationLog',
  NotificationLogSchema
);
