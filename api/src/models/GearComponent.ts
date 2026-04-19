import mongoose, { Schema, Document, Types } from 'mongoose';

/**
 * GearComponent — a single piece of trackable gear-life that the user wants
 * to keep an eye on (a pair of running shoes, a bike chain, a tire, etc.).
 *
 * Tracks consumption against a `lifeLimit` in `unit`s (miles / km / hours /
 * sessions). When `currentValue / lifeLimit` crosses `warningThreshold` the
 * worker enqueues a "gear approaching retirement" push; when it reaches the
 * full limit the worker enqueues a "ready to retire" push and auto-flips
 * `status` to `retired` (see worker/src/jobs/gearMileageAlert.ts and
 * api/src/modules/gear/routes.ts log-usage handler).
 *
 * Optional `deviceId` links the component to a paired BLE device (a smart
 * bike, an earbud case, etc.) so DeviceDetailView can surface a usage badge.
 */

export const GEAR_KINDS = [
  'shoe',
  'chain',
  'tire',
  'cassette',
  'helmet',
  'battery',
  'other',
] as const;

export const GEAR_UNITS = ['miles', 'km', 'hours', 'sessions'] as const;

export const GEAR_STATUSES = ['active', 'retired', 'archived'] as const;

export type GearKind = (typeof GEAR_KINDS)[number];
export type GearUnit = (typeof GEAR_UNITS)[number];
export type GearStatus = (typeof GEAR_STATUSES)[number];

export interface IGearComponent extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  deviceId: Types.ObjectId | null;
  name: string;
  kind: GearKind;
  unit: GearUnit;
  lifeLimit: number;
  warningThreshold: number;
  currentValue: number;
  status: GearStatus;
  retiredAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

const GearComponentSchema = new Schema<IGearComponent>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    deviceId: { type: Schema.Types.ObjectId, ref: 'Device', default: null },
    name: { type: String, required: true, trim: true, maxlength: 200 },
    kind: {
      type: String,
      enum: GEAR_KINDS,
      required: true,
    },
    unit: {
      type: String,
      enum: GEAR_UNITS,
      required: true,
    },
    lifeLimit: { type: Number, required: true, min: 0 },
    warningThreshold: { type: Number, default: 0.85, min: 0, max: 1 },
    currentValue: { type: Number, default: 0, min: 0 },
    status: {
      type: String,
      enum: GEAR_STATUSES,
      default: 'active',
    },
    retiredAt: { type: Date, default: null },
  },
  { timestamps: true },
);

GearComponentSchema.index({ userId: 1, status: 1 });
GearComponentSchema.index({ userId: 1, deviceId: 1 });

export const GearComponent = mongoose.model<IGearComponent>(
  'GearComponent',
  GearComponentSchema,
);
