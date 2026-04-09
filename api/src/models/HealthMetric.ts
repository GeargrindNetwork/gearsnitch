import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IHealthMetric extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  metricType:
    | 'weight'
    | 'height'
    | 'bmi'
    | 'active_calories'
    | 'steps'
    | 'resting_heart_rate'
    | 'workout_session';
  value: number;
  unit: 'kg' | 'lb' | 'cm' | 'in' | 'bmi' | 'kcal' | 'steps' | 'bpm';
  source: 'manual' | 'apple_health';
  recordedAt: Date;
  createdAt: Date;
}

const HealthMetricSchema = new Schema<IHealthMetric>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    metricType: {
      type: String,
      enum: [
        'weight',
        'height',
        'bmi',
        'active_calories',
        'steps',
        'resting_heart_rate',
        'workout_session',
      ],
      required: true,
    },
    value: { type: Number, required: true },
    unit: {
      type: String,
      enum: ['kg', 'lb', 'cm', 'in', 'bmi', 'kcal', 'steps', 'bpm'],
      required: true,
    },
    source: {
      type: String,
      enum: ['manual', 'apple_health'],
      required: true,
    },
    recordedAt: { type: Date, required: true },
  },
  { timestamps: { createdAt: true, updatedAt: false } }
);

HealthMetricSchema.index({ userId: 1, metricType: 1, recordedAt: -1 });

export const HealthMetric = mongoose.model<IHealthMetric>(
  'HealthMetric',
  HealthMetricSchema
);
