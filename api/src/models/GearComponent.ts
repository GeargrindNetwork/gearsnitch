import mongoose, { Schema, Document, Types } from 'mongoose';

/**
 * GearComponent — a piece of trackable gear (e.g. running shoes, bike,
 * chain, tires, chest strap). Mileage/time/session counters accrue as
 * workouts complete so we can fire retirement alerts (see backlog item #4).
 *
 * This is the minimal shape introduced alongside item #9 (auto-gear
 * assignment by activity type). PR #55 ships the richer UX + admin flows,
 * but the model lives here so routing/typing compiles independently.
 */

export const GEAR_KINDS = [
  'shoes',
  'bike',
  'tire',
  'chain',
  'chest_strap',
  'helmet',
  'other',
] as const;

export type GearKind = (typeof GEAR_KINDS)[number];

export const GEAR_UNITS = ['miles', 'km', 'hours', 'sessions'] as const;
export type GearUnit = (typeof GEAR_UNITS)[number];

export interface IGearComponent extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  name: string;
  kind: GearKind;
  unit: GearUnit;
  currentValue: number;
  retirementThreshold: number | null;
  retiredAt: Date | null;
  notes?: string | null;
  createdAt: Date;
  updatedAt: Date;
}

const GearComponentSchema = new Schema<IGearComponent>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    kind: {
      type: String,
      enum: GEAR_KINDS,
      required: true,
    },
    unit: {
      type: String,
      enum: GEAR_UNITS,
      required: true,
      default: 'miles',
    },
    currentValue: { type: Number, default: 0, min: 0 },
    retirementThreshold: { type: Number, default: null, min: 0 },
    retiredAt: { type: Date, default: null },
    notes: { type: String, default: null, maxlength: 2000 },
  },
  { timestamps: true },
);

GearComponentSchema.index({ userId: 1, kind: 1 });
GearComponentSchema.index({ userId: 1, retiredAt: 1 });

/**
 * Log usage against a gear component. Returns the updated document or null
 * if the gear doesn't belong to the user or is already retired. Caller is
 * expected to translate workout metrics (distanceMeters, durationSeconds,
 * sessionCount) into the gear's `unit` before calling.
 *
 * NB: The auto-attach flow in `/workouts` and `/runs` calls this when a
 * workout closes; keep the math here authoritative so PR #55's UI can reuse it.
 */
export async function logGearUsage(
  gearId: Types.ObjectId,
  userId: Types.ObjectId,
  amount: number,
): Promise<IGearComponent | null> {
  if (!Number.isFinite(amount) || amount <= 0) {
    return null;
  }

  return GearComponent.findOneAndUpdate(
    { _id: gearId, userId, retiredAt: null },
    { $inc: { currentValue: amount } },
    { new: true },
  );
}

export const GearComponent = mongoose.model<IGearComponent>(
  'GearComponent',
  GearComponentSchema,
);
