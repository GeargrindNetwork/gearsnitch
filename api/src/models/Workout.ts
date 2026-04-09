import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IWorkoutSet {
  reps: number;
  weightKg: number;
}

export interface IWorkoutExercise {
  name: string;
  sets: IWorkoutSet[];
}

export interface IWorkout extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  gymId: Types.ObjectId | null;
  name: string;
  startedAt: Date;
  endedAt: Date | null;
  durationMinutes: number;
  exercises: IWorkoutExercise[];
  notes?: string;
  source: 'manual' | 'apple_health';
  createdAt: Date;
  updatedAt: Date;
}

const WorkoutSetSchema = new Schema<IWorkoutSet>(
  {
    reps: { type: Number, required: true },
    weightKg: { type: Number, required: true },
  },
  { _id: false }
);

const WorkoutExerciseSchema = new Schema<IWorkoutExercise>(
  {
    name: { type: String, required: true },
    sets: { type: [WorkoutSetSchema], default: [] },
  },
  { _id: false }
);

const WorkoutSchema = new Schema<IWorkout>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    gymId: { type: Schema.Types.ObjectId, ref: 'Gym', default: null },
    name: { type: String, required: true },
    startedAt: { type: Date, required: true },
    endedAt: { type: Date, default: null },
    durationMinutes: { type: Number, default: 0 },
    exercises: { type: [WorkoutExerciseSchema], default: [] },
    notes: { type: String },
    source: {
      type: String,
      enum: ['manual', 'apple_health'],
      default: 'manual',
    },
  },
  { timestamps: true }
);

WorkoutSchema.index({ userId: 1, startedAt: -1 });
WorkoutSchema.index({ gymId: 1 });

export const Workout = mongoose.model<IWorkout>('Workout', WorkoutSchema);
