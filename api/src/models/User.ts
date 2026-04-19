import mongoose, { Schema, Document, Types } from 'mongoose';
import type { PermissionStateValue } from '../utils/permissionsState.js';

export interface IUser extends Document {
  _id: Types.ObjectId;
  email: string;
  emailHash: string;
  displayName: string;
  photoUrl?: string;
  referralCode?: string | null;
  /**
   * Post-install referral attribution: the User._id of the referrer that
   * brought this user in (typically resolved by `POST /api/v1/referrals/claim`
   * after a successful sign-in). Set once and only once — the claim endpoint
   * is idempotent and refuses to overwrite an existing value.
   */
  referredBy?: Types.ObjectId | null;
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
  /**
   * Stripe customer ID, persisted on first payment-flow invocation.
   * Avoids a global `stripe.customers.list({ email })` lookup that was
   * race-unsafe and could return the wrong customer if two users ever
   * shared an email. See PaymentService.getOrCreateStripeCustomer.
   */
  stripeCustomerId?: string | null;
  onboardingCompletedAt: Date | null;
  permissionsState: {
    bluetooth: PermissionStateValue | boolean;
    location: PermissionStateValue | boolean;
    backgroundLocation: PermissionStateValue | boolean;
    notifications: PermissionStateValue | boolean;
    healthKit: PermissionStateValue | boolean;
  };
  preferences: {
    pushEnabled: boolean;
    panicAlertsEnabled: boolean;
    disconnectAlertsEnabled: boolean;
    /**
     * Opt-out flag for the post-workout / post-run summary push (item #27).
     * Default `false` — meaning the summary push is ON. Users disable it from
     * the iOS Settings → Notifications screen.
     */
    workoutSummaryPushDisabled: boolean;
    custom?: Record<string, string>;
    /**
     * Strava-style "default gear per activity type" (backlog item #9).
     * Keyed by HKWorkoutActivityType rawValue (string) — e.g. 'running',
     * 'cycling', 'walking', 'hiking', 'strengthTraining'. Values are
     * GearComponent._id references. Stored as Mixed because the key set
     * is open-ended (Apple adds new activity types each WWDC).
     */
    defaultGearByActivity?: Record<string, Types.ObjectId | null>;
  };
  deletionRequestedAt: Date | null;
  deletionScheduledFor: Date | null;
  deletedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

const UserSchema = new Schema<IUser>(
  {
    email: { type: String, required: true },
    emailHash: { type: String, required: true },
    displayName: { type: String, required: true },
    photoUrl: { type: String },
    referralCode: { type: String, default: null, sparse: true },
    referredBy: { type: Schema.Types.ObjectId, ref: 'User', default: null },
    googleId: { type: String, sparse: true },
    appleId: { type: String, sparse: true },
    authProviders: { type: [String], default: [] },
    roles: { type: [String], default: ['user'] },
    status: { type: String, default: 'active' },
    stripeCustomerId: { type: String, default: null, sparse: true },
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
      bluetooth: { type: Schema.Types.Mixed, default: 'not_determined' },
      location: { type: Schema.Types.Mixed, default: 'not_determined' },
      backgroundLocation: { type: Schema.Types.Mixed, default: 'not_determined' },
      notifications: { type: Schema.Types.Mixed, default: 'not_determined' },
      healthKit: { type: Schema.Types.Mixed, default: 'not_determined' },
    },
    preferences: {
      pushEnabled: { type: Boolean, default: false },
      panicAlertsEnabled: { type: Boolean, default: false },
      disconnectAlertsEnabled: { type: Boolean, default: false },
      // Opt-out for post-session summary pushes (item #27). Default false
      // (= push enabled). Users flip via Settings → Notifications.
      workoutSummaryPushDisabled: { type: Boolean, default: false },
      custom: { type: Schema.Types.Mixed, default: {} },
      // Backlog item #9: per-HKWorkoutActivityType default GearComponent.
      // Open-ended key set, ObjectId values. Writes are validated against
      // the caller's GearComponent ownership in the route layer.
      defaultGearByActivity: { type: Schema.Types.Mixed, default: {} },
    },
    deletionRequestedAt: { type: Date, default: null },
    deletionScheduledFor: { type: Date, default: null },
    deletedAt: { type: Date, default: null },
  },
  { timestamps: true }
);

UserSchema.index({ emailHash: 1 }, { unique: true });
UserSchema.index({ referralCode: 1 }, { unique: true, sparse: true });
UserSchema.index({ googleId: 1 }, { unique: true, sparse: true });
UserSchema.index({ appleId: 1 }, { unique: true, sparse: true });
UserSchema.index({ roles: 1 });
UserSchema.index({ createdAt: 1 });
UserSchema.index({ email: 1 });
UserSchema.index({ status: 1 });
UserSchema.index({ deletedAt: 1 });
UserSchema.index({ stripeCustomerId: 1 }, { sparse: true });
// Sparse index — only the small subset of users that have been attributed to
// a referrer carry the field, and we query by it when computing referrer
// dashboards. Keep it sparse to avoid bloating the index with NULLs.
UserSchema.index({ referredBy: 1 }, { sparse: true });

export const User = mongoose.model<IUser>('User', UserSchema);
