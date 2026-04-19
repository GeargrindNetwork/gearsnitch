import mongoose, { Schema, Document } from 'mongoose';

/**
 * Tracks webhook events (Apple App Store Server Notifications v2,
 * Stripe, etc.) that have already been processed so duplicate deliveries
 * become idempotent no-ops.
 *
 * TTL: documents expire ~7 days after insert. Stripe retries for up to
 * 3 days; Apple retries for up to 5 days. 7 days gives headroom without
 * bloating the collection.
 */
export interface IProcessedWebhookEvent extends Document {
  eventId: string;       // Stripe event.id OR Apple notificationUUID
  provider: string;      // 'stripe' | 'apple'
  type: string;          // Stripe event type OR Apple notificationType
  createdAt: Date;
}

const ProcessedWebhookEventSchema = new Schema<IProcessedWebhookEvent>(
  {
    eventId: { type: String, required: true },
    provider: { type: String, required: true, default: 'stripe' },
    type: { type: String, required: true },
    createdAt: { type: Date, default: () => new Date() },
  },
  { versionKey: false }
);

// Unique on (provider, eventId) — duplicate inserts throw E11000 which we
// interpret as "already processed".
ProcessedWebhookEventSchema.index(
  { provider: 1, eventId: 1 },
  { unique: true }
);

// TTL: purge after 7 days (604800 seconds).
ProcessedWebhookEventSchema.index(
  { createdAt: 1 },
  { expireAfterSeconds: 60 * 60 * 24 * 7 }
);

export const ProcessedWebhookEvent = mongoose.model<IProcessedWebhookEvent>(
  'ProcessedWebhookEvent',
  ProcessedWebhookEventSchema
);
