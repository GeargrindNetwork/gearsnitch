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
  /**
   * Primary gear attached to this workout (backlog item #9). Set either
   * explicitly by the client or auto-derived from
   * User.preferences.defaultGearByActivity[activityType] on create.
   * `gearIds` carries multi-gear attachments (e.g. shoes + chest strap);
   * `gearId` is kept as a convenience handle for single-gear lookups and
   * mileage increments on completion.
   */
  gearId: Types.ObjectId | null;
  gearIds: Types.ObjectId[];
  /** HKWorkoutActivityType rawValue string, used to resolve default gear. */
  activityType?: string | null;
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
    activityType: { type: String, default: null },
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
WorkoutSchema.index({ gearId: 1 }, { sparse: true });

export const Workout = mongoose.model<IWorkout>('Workout', WorkoutSchema);
