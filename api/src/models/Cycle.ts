import mongoose, { Schema, Document, Types } from 'mongoose';

export type CycleType = 'peptide' | 'steroid' | 'mixed' | 'other';
export type CycleStatus = 'planned' | 'active' | 'paused' | 'completed' | 'archived';
export type CycleCompoundCategory = 'peptide' | 'steroid' | 'support' | 'pct' | 'other';
export type CycleDoseUnit = 'mg' | 'mcg' | 'iu' | 'ml' | 'units';
export type CycleRoute = 'injection' | 'oral' | 'topical' | 'other';

export interface ICycleCompoundPlan {
  compoundName: string;
  compoundCategory: CycleCompoundCategory;
  targetDose: number | null;
  doseUnit: CycleDoseUnit;
  route: CycleRoute | null;
}

export interface ICycle extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  name: string;
  type: CycleType;
  status: CycleStatus;
  startDate: Date;
  endDate: Date | null;
  timezone: string;
  notes: string | null;
  tags: string[];
  compounds: ICycleCompoundPlan[];
  createdAt: Date;
  updatedAt: Date;
}

const CycleCompoundPlanSchema = new Schema<ICycleCompoundPlan>(
  {
    compoundName: { type: String, required: true, trim: true },
    compoundCategory: {
      type: String,
      enum: ['peptide', 'steroid', 'support', 'pct', 'other'],
      default: 'other',
    },
    targetDose: { type: Number, default: null },
    doseUnit: {
      type: String,
      enum: ['mg', 'mcg', 'iu', 'ml', 'units'],
      default: 'mg',
    },
    route: {
      type: String,
      enum: ['injection', 'oral', 'topical', 'other'],
      default: null,
    },
  },
  { _id: false },
);

const CycleSchema = new Schema<ICycle>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    name: { type: String, required: true, trim: true },
    type: {
      type: String,
      enum: ['peptide', 'steroid', 'mixed', 'other'],
      default: 'other',
    },
    status: {
      type: String,
      enum: ['planned', 'active', 'paused', 'completed', 'archived'],
      default: 'planned',
    },
    startDate: { type: Date, required: true },
    endDate: { type: Date, default: null },
    timezone: { type: String, default: 'UTC', trim: true },
    notes: { type: String, default: null },
    tags: { type: [String], default: [] },
    compounds: { type: [CycleCompoundPlanSchema], default: [] },
  },
  { timestamps: true },
);

CycleSchema.index({ userId: 1, updatedAt: -1 });
CycleSchema.index({ userId: 1, status: 1, startDate: -1 });
CycleSchema.index({ userId: 1, startDate: -1, endDate: 1 });

export const Cycle = mongoose.model<ICycle>('Cycle', CycleSchema);
