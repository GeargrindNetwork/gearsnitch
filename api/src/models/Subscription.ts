import mongoose, { Schema, Document, Types } from 'mongoose';

export interface ISubscription extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  provider: string;
  providerOriginalTransactionId: string;
  productId: string;
  status: 'active' | 'expired' | 'grace_period' | 'cancelled';
  purchaseDate: Date;
  expiryDate: Date;
  lastValidatedAt: Date;
  extensionDays: number;
  createdAt: Date;
  updatedAt: Date;
}

const SubscriptionSchema = new Schema<ISubscription>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    provider: { type: String, default: 'apple' },
    providerOriginalTransactionId: { type: String, required: true },
    productId: { type: String, required: true },
    status: {
      type: String,
      enum: ['active', 'expired', 'grace_period', 'cancelled'],
      required: true,
    },
    purchaseDate: { type: Date, required: true },
    expiryDate: { type: Date, required: true },
    lastValidatedAt: { type: Date, required: true },
    extensionDays: { type: Number, default: 0 },
  },
  { timestamps: true }
);

SubscriptionSchema.index(
  { provider: 1, providerOriginalTransactionId: 1 },
  { unique: true }
);
SubscriptionSchema.index({ userId: 1, status: 1 });
SubscriptionSchema.index({ expiryDate: 1 });

export const Subscription = mongoose.model<ISubscription>(
  'Subscription',
  SubscriptionSchema
);
