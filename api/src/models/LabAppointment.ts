import mongoose, { Schema, Document, Types } from 'mongoose';

export interface ILabAppointment extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  productId: string;
  appointmentDate: Date;
  location: string;
  provider: string;
  status: 'confirmed' | 'completed' | 'cancelled';
  amountCharged: number;
  paymentId?: string;
  notes?: string;
  createdAt: Date;
  updatedAt: Date;
}

const LabAppointmentSchema = new Schema<ILabAppointment>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    productId: { type: String, required: true },
    appointmentDate: { type: Date, required: true },
    location: { type: String, required: true },
    provider: { type: String, required: true },
    status: {
      type: String,
      enum: ['confirmed', 'completed', 'cancelled'],
      default: 'confirmed',
    },
    amountCharged: { type: Number, required: true },
    paymentId: { type: String },
    notes: { type: String },
  },
  { timestamps: true }
);

LabAppointmentSchema.index({ userId: 1, appointmentDate: -1 });

export const LabAppointment = mongoose.model<ILabAppointment>(
  'LabAppointment',
  LabAppointmentSchema
);
