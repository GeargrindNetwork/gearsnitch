import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IGym extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  name: string;
  isDefault: boolean;
  location: {
    type: 'Point';
    coordinates: [number, number];
  };
  radiusMeters: number;
  createdAt: Date;
  updatedAt: Date;
}

const GymSchema = new Schema<IGym>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    name: { type: String, required: true },
    isDefault: { type: Boolean, default: false },
    location: {
      type: { type: String, enum: ['Point'], default: 'Point', required: true },
      coordinates: { type: [Number], required: true },
    },
    radiusMeters: { type: Number, default: 150 },
  },
  { timestamps: true }
);

GymSchema.index({ userId: 1 });
GymSchema.index({ userId: 1, isDefault: 1 });
GymSchema.index({ location: '2dsphere' });

export const Gym = mongoose.model<IGym>('Gym', GymSchema);
