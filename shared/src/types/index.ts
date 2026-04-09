// ─── GeoJSON ───────────────────────────────────────────────────────────────

/** GeoJSON Point for location fields */
export interface GeoJSONPoint {
  type: 'Point';
  coordinates: [longitude: number, latitude: number];
}

// ─── User ──────────────────────────────────────────────────────────────────

/** User permission state tracking */
export interface IPermissionsState {
  notificationsEnabled: boolean;
  bluetoothEnabled: boolean;
  locationEnabled: boolean;
  healthKitEnabled: boolean;
}

/** User preferences */
export interface IUserPreferences {
  units: 'imperial' | 'metric';
  theme: 'dark' | 'light' | 'system';
  disconnectAlertDelay: number;
  panicAlertEnabled: boolean;
}

/** Core user profile */
export interface IUser {
  _id: string;
  email: string;
  /** SHA-256 hash of normalized email for Gravatar / dedup */
  emailHash: string;
  displayName: string;
  photoUrl?: string;
  /** OAuth providers linked to this account */
  authProviders: ('apple' | 'google')[];
  roles: ('user' | 'admin' | 'support')[];
  status: 'active' | 'suspended' | 'deleted';
  /** Default gym for auto-monitoring */
  defaultGymId?: string;
  /** Timestamp when the user completed onboarding */
  onboardingCompletedAt?: string;
  permissionsState: IPermissionsState;
  preferences: IUserPreferences;
  createdAt: string;
  updatedAt: string;
}

// ─── Session ───────────────────────────────────────────────────────────────

/** Authenticated session (JWT refresh token record) */
export interface ISession {
  _id: string;
  userId: string;
  /** JWT ID claim — uniquely identifies this refresh token */
  jti: string;
  deviceName?: string;
  platform?: 'ios' | 'watchos' | 'web';
  ipAddress?: string;
  userAgent?: string;
  expiresAt: string;
  revokedAt?: string;
  createdAt: string;
}

// ─── Referral ──────────────────────────────────────────────────────────────

/** Referral tracking between users */
export interface IReferral {
  _id: string;
  referrerUserId: string;
  referredUserId: string;
  referralCode: string;
  status: 'pending' | 'qualified' | 'rewarded' | 'rejected';
  /** Number of free days granted as reward */
  rewardDays: number;
  qualifiedAt?: string;
  rewardedAt?: string;
  /** Human-readable reason for rejection or qualification */
  reason?: string;
  createdAt: string;
  updatedAt: string;
}

// ─── Subscription ──────────────────────────────────────────────────────────

/** In-app subscription record synced from App Store / Google Play */
export interface ISubscription {
  _id: string;
  userId: string;
  provider: 'apple' | 'google';
  /** Original transaction ID from the store */
  providerOriginalTransactionId: string;
  productId: string;
  status: 'active' | 'expired' | 'grace_period' | 'cancelled';
  purchaseDate: string;
  expiryDate: string;
  lastValidatedAt: string;
  /** Bonus days added via referral or promo */
  extensionDays: number;
  createdAt: string;
  updatedAt: string;
}

// ─── Device ────────────────────────────────────────────────────────────────

/** BLE-connected device (gear tracker) */
export interface IDevice {
  _id: string;
  userId: string;
  name: string;
  type: 'earbuds' | 'tracker' | 'belt' | 'bag' | 'other';
  /** BLE peripheral identifier or serial number */
  identifier: string;
  hardwareModel?: string;
  firmwareVersion?: string;
  status:
    | 'registered'
    | 'active'
    | 'inactive'
    | 'connected'
    | 'disconnected'
    | 'lost'
    | 'reconnected';
  monitoringEnabled: boolean;
  lastSeenAt?: string;
  lastSeenLocation?: GeoJSONPoint;
  lastSignalStrength?: number;
  createdAt: string;
  updatedAt: string;
}

// ─── Device Share ──────────────────────────────────────────────────────────

/** Shared device access between users */
export interface IDeviceShare {
  _id: string;
  deviceId: string;
  ownerUserId: string;
  sharedWithUserId: string;
  canReceiveAlerts: boolean;
  createdAt: string;
  updatedAt: string;
}

// ─── Gym ───────────────────────────────────────────────────────────────────

/** Gym geofence location */
export interface IGym {
  _id: string;
  userId: string;
  name: string;
  isDefault: boolean;
  location: GeoJSONPoint;
  /** Geofence radius in meters */
  radiusMeters: number;
  createdAt: string;
  updatedAt: string;
}

// ─── Alert ─────────────────────────────────────────────────────────────────

/** Device or safety alert */
export interface IAlert {
  _id: string;
  userId: string;
  deviceId: string;
  type:
    | 'disconnect_warning'
    | 'panic_alarm'
    | 'reconnect_found'
    | 'gym_entry_activate'
    | 'gym_exit_deactivate';
  severity: 'low' | 'medium' | 'high' | 'critical';
  status: 'open' | 'acknowledged' | 'resolved';
  triggeredAt: string;
  resolvedAt?: string;
  /** Arbitrary metadata attached to the alert (e.g. last known location) */
  metadata?: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
}

// ─── Emergency Contact ─────────────────────────────────────────────────────

/** Emergency contact for panic/disconnect alerts */
export interface IEmergencyContact {
  _id: string;
  userId: string;
  name: string;
  phone: string;
  email?: string;
  notifyOnPanic: boolean;
  notifyOnDisconnect: boolean;
  createdAt: string;
  updatedAt: string;
}

// ─── Notification ──────────────────────────────────────────────────────────

/** APNS device token registration */
export interface INotificationToken {
  _id: string;
  userId: string;
  platform: 'ios' | 'watchos';
  token: string;
  environment: 'sandbox' | 'production';
  active: boolean;
  lastUsedAt?: string;
  createdAt: string;
  updatedAt: string;
}

/** Push notification delivery log entry */
export interface INotificationLog {
  _id: string;
  userId: string;
  tokenId: string;
  notificationType: string;
  sentAt: string;
  deliveredAt?: string;
  openedAt?: string;
  failureReason?: string;
  createdAt: string;
}

// ─── Health ────────────────────────────────────────────────────────────────

/** Single health metric data point */
export interface IHealthMetric {
  _id: string;
  userId: string;
  metricType: string;
  value: number;
  unit: string;
  source: 'manual' | 'apple_health';
  recordedAt: string;
  createdAt: string;
}

/** Daily nutrition targets */
export interface INutritionGoal {
  _id: string;
  userId: string;
  dailyCalorieTarget: number;
  proteinTargetG: number;
  carbsTargetG: number;
  fatTargetG: number;
  fiberTargetG: number;
  waterTargetMl: number;
  createdAt: string;
  updatedAt: string;
}

/** Individual meal log entry */
export interface IMeal {
  _id: string;
  userId: string;
  date: string;
  mealType: 'breakfast' | 'lunch' | 'dinner' | 'snack';
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber?: number;
  sugar?: number;
  createdAt: string;
  updatedAt: string;
}

/** Daily water intake log entry */
export interface IWaterLog {
  _id: string;
  userId: string;
  date: string;
  amountMl: number;
  loggedAt: string;
  createdAt: string;
}

// ─── Workout ───────────────────────────────────────────────────────────────

/** Single set within an exercise */
export interface IExerciseSet {
  reps?: number;
  weight?: number;
  durationSeconds?: number;
}

/** Exercise entry within a workout */
export interface IExercise {
  name: string;
  sets: IExerciseSet[];
}

/** Workout session log */
export interface IWorkout {
  _id: string;
  userId: string;
  gymId?: string;
  name: string;
  startedAt: string;
  endedAt?: string;
  durationMinutes?: number;
  exercises: IExercise[];
  notes?: string;
  source?: string;
  createdAt: string;
  updatedAt: string;
}

// ─── Store ─────────────────────────────────────────────────────────────────

/** Product compliance information */
export interface IProductCompliance {
  requiresAgeVerification: boolean;
  restrictedStates?: string[];
  disclaimer?: string;
}

/** Store product listing */
export interface IStoreProduct {
  _id: string;
  sku: string;
  name: string;
  slug: string;
  description: string;
  categoryId: string;
  price: number;
  currency: string;
  inventory: number;
  active: boolean;
  images: string[];
  compliance: IProductCompliance;
  createdAt: string;
  updatedAt: string;
}

/** Product category */
export interface IStoreCategory {
  _id: string;
  name: string;
  slug: string;
  active: boolean;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
}

/** Cart line item */
export interface ICartItem {
  productId: string;
  quantity: number;
  price: number;
}

/** Shopping cart */
export interface IStoreCart {
  _id: string;
  userId: string;
  items: ICartItem[];
  currency: string;
  subtotal: number;
  createdAt: string;
  updatedAt: string;
}

/** Order line item */
export interface IOrderItem {
  productId: string;
  sku: string;
  name: string;
  quantity: number;
  price: number;
}

/** Shipping address */
export interface IShippingAddress {
  name: string;
  line1: string;
  line2?: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
}

/** Store order */
export interface IStoreOrder {
  _id: string;
  userId: string;
  orderNumber: string;
  status:
    | 'pending'
    | 'paid'
    | 'processing'
    | 'shipped'
    | 'delivered'
    | 'cancelled'
    | 'refunded';
  items: IOrderItem[];
  subtotal: number;
  tax: number;
  shipping: number;
  total: number;
  currency: string;
  shippingAddress: IShippingAddress;
  complianceAccepted: boolean;
  createdAt: string;
  updatedAt: string;
}

// ─── API Envelope ──────────────────────────────────────────────────────────

/** Standardized API error shape */
export interface ApiError {
  code: string;
  message: string;
}

/** Pagination / metadata for list responses */
export interface ApiMeta {
  page?: number;
  limit?: number;
  total?: number;
  [key: string]: unknown;
}

/** Standardized API response envelope */
export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  meta?: ApiMeta;
  error?: ApiError;
}
