import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IGymSessionEvent {
  type: string;
  timestamp: Date;
  metadata?: unknown;
}

export interface IGymSession extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  gymId: Types.ObjectId;
  gymName?: string;
  startedAt: Date;
  endedAt: Date | null;
  durationMinutes: number;
  events: IGymSessionEvent[];
  source: 'manual' | 'geofence' | 'widget';
  createdAt: Date;
  updatedAt: Date;
}

const GymSessionEventSchema = new Schema<IGymSessionEvent>(
  {
    type: { type: String, required: true },
    timestamp: { type: Date, required: true },
    metadata: { type: Schema.Types.Mixed },
  },
  { _id: false },
);

const GymSessionSchema = new Schema<IGymSession>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    gymId: { type: Schema.Types.ObjectId, ref: 'Gym', required: true },
    gymName: { type: String },
    startedAt: { type: Date, required: true },
    endedAt: { type: Date, default: null },
    durationMinutes: { type: Number, default: 0 },
    events: { type: [GymSessionEventSchema], default: [] },
    source: {
      type: String,
      enum: ['manual', 'geofence', 'widget'],
      default: 'manual',
    },
  },
  { timestamps: true },
);

GymSessionSchema.index({ userId: 1, startedAt: -1 });
GymSessionSchema.index({ gymId: 1 });

export const GymSession = mongoose.model<IGymSession>('GymSession', GymSessionSchema);
