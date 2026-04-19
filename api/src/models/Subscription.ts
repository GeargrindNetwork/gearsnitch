import mongoose, { Schema, Document, Types } from 'mongoose';

export type SubscriptionStatus =
  | 'active'
  | 'expired'
  | 'grace_period'
  | 'cancelled'
  | 'past_due'
  | 'refunded'
  | 'revoked';

export interface ISubscription extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  provider: string;
  providerOriginalTransactionId: string;
  originalTransactionId?: string;
  productId: string;
  status: SubscriptionStatus;
  purchaseDate: Date;
  expiryDate: Date;
  lastValidatedAt: Date;
  extensionDays: number;
  autoRenew: boolean;
  stripeSubscriptionId?: string | null;
  stripeCustomerId?: string | null;
  cancelledAt?: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

const SubscriptionSchema = new Schema<ISubscription>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    provider: { type: String, default: 'apple' },
    providerOriginalTransactionId: { type: String, required: true },
    originalTransactionId: { type: String },
    productId: { type: String, required: true },
    status: {
      type: String,
      enum: [
        'active',
        'expired',
        'grace_period',
        'cancelled',
        'past_due',
        'refunded',
        'revoked',
      ],
      required: true,
    },
    purchaseDate: { type: Date, required: true },
    expiryDate: { type: Date, required: true },
    lastValidatedAt: { type: Date, required: true },
    extensionDays: { type: Number, default: 0 },
    autoRenew: { type: Boolean, default: true },
    stripeSubscriptionId: { type: String, default: null, sparse: true },
    stripeCustomerId: { type: String, default: null },
    cancelledAt: { type: Date, default: null },
  },
  { timestamps: true }
);

SubscriptionSchema.index(
  { provider: 1, providerOriginalTransactionId: 1 },
  { unique: true }
);
SubscriptionSchema.index({ userId: 1, status: 1 });
SubscriptionSchema.index({ expiryDate: 1 });
SubscriptionSchema.index({ originalTransactionId: 1 });
SubscriptionSchema.index({ stripeSubscriptionId: 1 }, { sparse: true });

export const Subscription = mongoose.model<ISubscription>(
  'Subscription',
  SubscriptionSchema
);
