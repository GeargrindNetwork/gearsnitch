import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IMeal extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  /** YYYY-MM-DD */
  date: string;
  mealType: 'breakfast' | 'lunch' | 'dinner' | 'snack';
  name: string;
  calories?: number;
  protein?: number;
  carbs?: number;
  fat?: number;
  fiber?: number;
  sugar?: number;
  createdAt: Date;
  updatedAt: Date;
}

const MealSchema = new Schema<IMeal>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    date: { type: String, required: true },
    mealType: {
      type: String,
      enum: ['breakfast', 'lunch', 'dinner', 'snack'],
      required: true,
    },
    name: { type: String, required: true },
    calories: { type: Number },
    protein: { type: Number },
    carbs: { type: Number },
    fat: { type: Number },
    fiber: { type: Number },
    sugar: { type: Number },
  },
  { timestamps: true }
);

MealSchema.index({ userId: 1, date: 1, mealType: 1 });
MealSchema.index({ createdAt: 1 });

export const Meal = mongoose.model<IMeal>('Meal', MealSchema);
