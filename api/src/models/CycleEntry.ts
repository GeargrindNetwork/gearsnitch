import mongoose, { Schema, Document, Types } from 'mongoose';

export type CycleEntryCompoundCategory = 'peptide' | 'steroid' | 'support' | 'pct' | 'other';
export type CycleEntryRoute = 'injection' | 'oral' | 'topical' | 'other';
export type CycleEntryDoseUnit = 'mg' | 'mcg' | 'iu' | 'ml' | 'units';
export type CycleEntrySource = 'manual' | 'ios' | 'web' | 'imported';

export interface ICycleEntry extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  cycleId: Types.ObjectId;
  compoundName: string;
  compoundCategory: CycleEntryCompoundCategory;
  route: CycleEntryRoute;
  occurredAt: Date;
  dateKey: string;
  plannedDose: number | null;
  actualDose: number | null;
  doseUnit: CycleEntryDoseUnit;
  notes: string | null;
  source: CycleEntrySource;
  createdAt: Date;
  updatedAt: Date;
}

const CycleEntrySchema = new Schema<ICycleEntry>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    cycleId: { type: Schema.Types.ObjectId, ref: 'Cycle', required: true },
    compoundName: { type: String, required: true, trim: true },
    compoundCategory: {
      type: String,
      enum: ['peptide', 'steroid', 'support', 'pct', 'other'],
      default: 'other',
    },
    route: {
      type: String,
      enum: ['injection', 'oral', 'topical', 'other'],
      default: 'other',
    },
    occurredAt: { type: Date, required: true },
    dateKey: { type: String, required: true },
    plannedDose: { type: Number, default: null },
    actualDose: { type: Number, default: null },
    doseUnit: {
      type: String,
      enum: ['mg', 'mcg', 'iu', 'ml', 'units'],
      default: 'mg',
    },
    notes: { type: String, default: null },
    source: {
      type: String,
      enum: ['manual', 'ios', 'web', 'imported'],
      default: 'manual',
    },
  },
  { timestamps: true },
);

CycleEntrySchema.index({ userId: 1, cycleId: 1, occurredAt: -1 });
CycleEntrySchema.index({ userId: 1, dateKey: 1, occurredAt: -1 });
CycleEntrySchema.index({ cycleId: 1, dateKey: 1 });

export const CycleEntry = mongoose.model<ICycleEntry>('CycleEntry', CycleEntrySchema);
