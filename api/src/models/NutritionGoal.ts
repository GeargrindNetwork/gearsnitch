import mongoose, { Schema, Document, Types } from 'mongoose';

export interface INutritionGoal extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  dailyCalorieTarget: number;
  proteinTargetG: number;
  carbsTargetG: number;
  fatTargetG: number;
  fiberTargetG: number;
  waterTargetMl: number;
  createdAt: Date;
  updatedAt: Date;
}

const NutritionGoalSchema = new Schema<INutritionGoal>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    dailyCalorieTarget: { type: Number, default: 2000 },
    proteinTargetG: { type: Number, default: 150 },
    carbsTargetG: { type: Number, default: 200 },
    fatTargetG: { type: Number, default: 65 },
    fiberTargetG: { type: Number, default: 30 },
    waterTargetMl: { type: Number, default: 2500 },
  },
  { timestamps: true }
);

NutritionGoalSchema.index({ userId: 1 }, { unique: true });

export const NutritionGoal = mongoose.model<INutritionGoal>(
  'NutritionGoal',
  NutritionGoalSchema
);
