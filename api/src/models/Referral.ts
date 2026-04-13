import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IReferral extends Document {
  _id: Types.ObjectId;
  referrerUserId: Types.ObjectId;
  referredUserId: Types.ObjectId | null;
  referralCode: string;
  status: 'pending' | 'qualified' | 'rewarded' | 'rejected';
  rewardDays: number;
  qualifiedAt?: Date;
  rewardedAt?: Date;
  reason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const ReferralSchema = new Schema<IReferral>(
  {
    referrerUserId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    referredUserId: { type: Schema.Types.ObjectId, ref: 'User', default: null },
    referralCode: { type: String, required: true },
    status: {
      type: String,
      enum: ['pending', 'qualified', 'rewarded', 'rejected'],
      default: 'pending',
    },
    rewardDays: { type: Number, default: 28 },
    qualifiedAt: { type: Date },
    rewardedAt: { type: Date },
    reason: { type: String },
  },
  { timestamps: true }
);

ReferralSchema.index({ referrerUserId: 1 });
ReferralSchema.index({ referredUserId: 1 });
ReferralSchema.index({ referralCode: 1 });

export const Referral = mongoose.model<IReferral>('Referral', ReferralSchema);
