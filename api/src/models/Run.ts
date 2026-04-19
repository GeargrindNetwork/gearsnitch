import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IRunPoint {
  latitude: number;
  longitude: number;
  timestamp: Date;
  altitudeMeters: number | null;
  horizontalAccuracyMeters: number | null;
  speedMetersPerSecond: number | null;
}

export interface IRun extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  /**
   * Primary gear attached to this run (backlog item #9). Typically a
   * `shoes` GearComponent. Auto-derived from
   * User.preferences.defaultGearByActivity.running on start when the
   * client doesn't supply one.
   */
  gearId: Types.ObjectId | null;
  gearIds: Types.ObjectId[];
  startedAt: Date;
  endedAt: Date | null;
  durationSeconds: number;
  distanceMeters: number;
  averagePaceSecondsPerKm: number | null;
  routePoints: IRunPoint[];
  source: 'ios' | 'manual';
  notes?: string | null;
  createdAt: Date;
  updatedAt: Date;
}

const RunPointSchema = new Schema<IRunPoint>(
  {
    latitude: { type: Number, required: true },
    longitude: { type: Number, required: true },
    timestamp: { type: Date, required: true },
    altitudeMeters: { type: Number, default: null },
    horizontalAccuracyMeters: { type: Number, default: null },
    speedMetersPerSecond: { type: Number, default: null },
  },
  { _id: false },
);

const RunSchema = new Schema<IRun>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    gearId: {
      type: Schema.Types.ObjectId,
      ref: 'GearComponent',
      default: null,
      sparse: true,
    },
    gearIds: {
      type: [{ type: Schema.Types.ObjectId, ref: 'GearComponent' }],
      default: [],
    },
    startedAt: { type: Date, required: true },
    endedAt: { type: Date, default: null },
    durationSeconds: { type: Number, default: 0 },
    distanceMeters: { type: Number, default: 0 },
    averagePaceSecondsPerKm: { type: Number, default: null },
    routePoints: { type: [RunPointSchema], default: [] },
    source: {
      type: String,
      enum: ['ios', 'manual'],
      default: 'ios',
    },
    notes: { type: String, default: null },
  },
  { timestamps: true },
);

RunSchema.index({ userId: 1, startedAt: -1 });
RunSchema.index({ userId: 1, endedAt: 1 });
RunSchema.index({ gearId: 1 }, { sparse: true });

export const Run = mongoose.model<IRun>('Run', RunSchema);
