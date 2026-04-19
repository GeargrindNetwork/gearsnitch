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
  /**
   * HealthKit `HKMedicationDose` UUID (string form). Sparse — only set when the
   * dose was either pushed to or pulled from Apple Health via the iOS
   * HealthKit Medications sync (item #7). Used to dedupe round-trips so a dose
   * created in GearSnitch and then read back from HealthKit on the next pull
   * does not get re-inserted as a duplicate row.
   */
  appleHealthDoseId: string | null;
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
    appleHealthDoseId: { type: String, default: null, sparse: true, index: true },
  },
  { timestamps: true },
);

MedicationDoseSchema.index({ userId: 1, dateKey: 1, category: 1, occurredAt: -1 });
MedicationDoseSchema.index({ userId: 1, dayOfYear: 1, occurredAt: -1 });
MedicationDoseSchema.index({ userId: 1, cycleId: 1, occurredAt: -1 });
// Sparse compound index — used to dedupe HealthKit-originated doses on a
// per-user basis. Only the rows that have been touched by the iOS HealthKit
// Medications sync (item #7) carry this field, so the index stays small.
MedicationDoseSchema.index(
  { userId: 1, appleHealthDoseId: 1 },
  { unique: true, sparse: true },
);

export const MedicationDose = mongoose.model<IMedicationDose>('MedicationDose', MedicationDoseSchema);
