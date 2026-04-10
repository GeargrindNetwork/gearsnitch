import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IUser extends Document {
  _id: Types.ObjectId;
  email: string;
  emailHash: string;
  displayName: string;
  photoUrl?: string;
  googleId?: string;
  appleId?: string;
  authProviders: string[];
  roles: string[];
  status: string;
  firstName?: string;
  lastName?: string;
  dateOfBirth?: Date;
  biologicalSex?: 'male' | 'female' | 'other';
  bloodType?: 'A+' | 'A-' | 'B+' | 'B-' | 'AB+' | 'AB-' | 'O+' | 'O-';
  heightCm?: number;
  weightKg?: number;
  defaultGymId: Types.ObjectId | null;
  onboardingCompletedAt: Date | null;
  permissionsState: {
    bluetooth: boolean;
    location: boolean;
    notifications: boolean;
  };
  preferences: {
    pushEnabled: boolean;
    panicAlertsEnabled: boolean;
    disconnectAlertsEnabled: boolean;
  };
  createdAt: Date;
  updatedAt: Date;
}

const UserSchema = new Schema<IUser>(
  {
    email: { type: String, required: true },
    emailHash: { type: String, required: true },
    displayName: { type: String, required: true },
    photoUrl: { type: String },
    googleId: { type: String, sparse: true },
    appleId: { type: String, sparse: true },
    authProviders: { type: [String], default: [] },
    roles: { type: [String], default: ['user'] },
    status: { type: String, default: 'active' },
    firstName: { type: String, default: null },
    lastName: { type: String, default: null },
    dateOfBirth: { type: Date, default: null },
    biologicalSex: {
      type: String,
      enum: ['male', 'female', 'other'],
      default: null,
    },
    bloodType: {
      type: String,
      enum: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
      default: null,
    },
    heightCm: { type: Number, default: null },
    weightKg: { type: Number, default: null },
    defaultGymId: { type: Schema.Types.ObjectId, ref: 'Gym', default: null },
    onboardingCompletedAt: { type: Date, default: null },
    permissionsState: {
      bluetooth: { type: Boolean, default: false },
      location: { type: Boolean, default: false },
      notifications: { type: Boolean, default: false },
    },
    preferences: {
      pushEnabled: { type: Boolean, default: false },
      panicAlertsEnabled: { type: Boolean, default: false },
      disconnectAlertsEnabled: { type: Boolean, default: false },
    },
  },
  { timestamps: true }
);

UserSchema.index({ emailHash: 1 }, { unique: true });
UserSchema.index({ googleId: 1 }, { unique: true, sparse: true });
UserSchema.index({ appleId: 1 }, { unique: true, sparse: true });
UserSchema.index({ roles: 1 });
UserSchema.index({ createdAt: 1 });

export const User = mongoose.model<IUser>('User', UserSchema);
