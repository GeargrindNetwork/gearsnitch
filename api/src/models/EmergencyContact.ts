import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IEmergencyContact extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  name: string;
  /** Encrypted at rest */
  phone: string;
  /** Encrypted at rest */
  email: string;
  notifyOnPanic: boolean;
  notifyOnDisconnect: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const EmergencyContactSchema = new Schema<IEmergencyContact>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    name: { type: String, required: true },
    /** Encrypted at rest */
    phone: { type: String, required: true },
    /** Encrypted at rest */
    email: { type: String, required: true },
    notifyOnPanic: { type: Boolean, default: true },
    notifyOnDisconnect: { type: Boolean, default: false },
  },
  { timestamps: true }
);

EmergencyContactSchema.index({ userId: 1 });

export const EmergencyContact = mongoose.model<IEmergencyContact>(
  'EmergencyContact',
  EmergencyContactSchema
);
