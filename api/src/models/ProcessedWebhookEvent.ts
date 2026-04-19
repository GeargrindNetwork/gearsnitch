import mongoose, { Schema, Document } from 'mongoose';

/**
 * Tracks webhook events (Apple App Store Server Notifications v2,
 * Stripe, etc.) that have already been processed so we can reject
 * duplicates and guarantee idempotency on retries.
 */
export interface IProcessedWebhookEvent extends Document {
  provider: string; // 'apple' | 'stripe'
  eventId: string; // Apple's notificationUUID, Stripe event.id, etc.
  notificationType?: string;
  processedAt: Date;
}

const ProcessedWebhookEventSchema = new Schema<IProcessedWebhookEvent>(
  {
    provider: { type: String, required: true },
    eventId: { type: String, required: true },
    notificationType: { type: String },
    processedAt: { type: Date, default: () => new Date() },
  },
  { timestamps: true },
);

ProcessedWebhookEventSchema.index(
  { provider: 1, eventId: 1 },
  { unique: true },
);

export const ProcessedWebhookEvent = mongoose.model<IProcessedWebhookEvent>(
  'ProcessedWebhookEvent',
  ProcessedWebhookEventSchema,
);
