import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IUser extends Document {
  _id: Types.ObjectId;
  email: string;
  emailHash: string;
  displayName: string;
  photoUrl?: string;
  authProviders: string[];
  roles: string[];
  status: string;
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
    authProviders: { type: [String], default: [] },
    roles: { type: [String], default: ['user'] },
    status: { type: String, default: 'active' },
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
UserSchema.index({ roles: 1 });
UserSchema.index({ createdAt: 1 });

export const User = mongoose.model<IUser>('User', UserSchema);
