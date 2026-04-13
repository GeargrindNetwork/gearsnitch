import mongoose, { Schema, Document, Types } from 'mongoose';

export type MedicationDoseCategory = 'steroid' | 'peptide' | 'oralMedication';
export type MedicationDoseUnit = 'mg' | 'mcg' | 'iu' | 'ml' | 'units';
export type MedicationDoseSource = 'manual' | 'ios' | 'web' | 'imported';

export interface IMedicationDoseAmount {
  value: number;
  unit: MedicationDoseUnit;
}

export interface IMedicationDose extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  cycleId: Types.ObjectId | null;
  dateKey: string;
  dayOfYear: number;
  category: MedicationDoseCategory;
  compoundName: string;
  dose: IMedicationDoseAmount;
  doseMg: number | null;
  occurredAt: Date;
  notes: string | null;
  source: MedicationDoseSource;
  createdAt: Date;
  updatedAt: Date;
}

const MedicationDoseAmountSchema = new Schema<IMedicationDoseAmount>(
  {
    value: { type: Number, required: true, min: 0 },
    unit: {
      type: String,
      enum: ['mg', 'mcg', 'iu', 'ml', 'units'],
      default: 'mg',
    },
  },
  { _id: false },
);

const MedicationDoseSchema = new Schema<IMedicationDose>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    cycleId: { type: Schema.Types.ObjectId, ref: 'Cycle', default: null },
    dateKey: { type: String, required: true },
    dayOfYear: { type: Number, required: true, min: 1, max: 366 },
    category: { type: String, enum: ['steroid', 'peptide', 'oralMedication'], required: true },
    compoundName: { type: String, required: true, trim: true },
    dose: { type: MedicationDoseAmountSchema, required: true },
    doseMg: { type: Number, default: null },
    occurredAt: { type: Date, required: true },
    notes: { type: String, default: null },
    source: {
      type: String,
      enum: ['manual', 'ios', 'web', 'imported'],
      default: 'manual',
    },
  },
  { timestamps: true },
);

MedicationDoseSchema.index({ userId: 1, dateKey: 1, category: 1, occurredAt: -1 });
MedicationDoseSchema.index({ userId: 1, dayOfYear: 1, occurredAt: -1 });
MedicationDoseSchema.index({ userId: 1, cycleId: 1, occurredAt: -1 });

export const MedicationDose = mongoose.model<IMedicationDose>('MedicationDose', MedicationDoseSchema);
