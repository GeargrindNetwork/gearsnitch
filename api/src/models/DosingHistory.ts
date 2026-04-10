import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IDosingHistory extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  substance: string;
  concentration: number;
  desiredDose: number;
  volumeInjected: number;
  reconstitutionVolume: number | null;
  notes: string | null;
  createdAt: Date;
}

const DosingHistorySchema = new Schema<IDosingHistory>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    substance: { type: String, required: true },
    concentration: { type: Number, required: true },
    desiredDose: { type: Number, required: true },
    volumeInjected: { type: Number, required: true },
    reconstitutionVolume: { type: Number, default: null },
    notes: { type: String, default: null },
  },
  { timestamps: { createdAt: true, updatedAt: false } },
);

DosingHistorySchema.index({ userId: 1, createdAt: -1 });

export const DosingHistory = mongoose.model<IDosingHistory>(
  'DosingHistory',
  DosingHistorySchema,
);
