import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IWaterLog extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  /** YYYY-MM-DD */
  date: string;
  amountMl: number;
  loggedAt: Date;
  createdAt: Date;
}

const WaterLogSchema = new Schema<IWaterLog>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    date: { type: String, required: true },
    amountMl: { type: Number, required: true },
    loggedAt: { type: Date, required: true },
  },
  { timestamps: { createdAt: true, updatedAt: false } }
);

WaterLogSchema.index({ userId: 1, date: 1 });

export const WaterLog = mongoose.model<IWaterLog>('WaterLog', WaterLogSchema);
