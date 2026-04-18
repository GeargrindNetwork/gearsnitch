// ─── GeoJSON ───────────────────────────────────────────────────────────────

/** GeoJSON Point for location fields */
export interface GeoJSONPoint {
  type: 'Point';
  coordinates: [longitude: number, latitude: number];
}

// ─── User ──────────────────────────────────────────────────────────────────

/**
 * Canonical per-permission grant state as reported by iOS (the source of
 * truth for the wire format). Matches `PermissionStatus` in
 * `client-ios/GearSnitch/Shared/Models/User.swift`.
 */
export type PermissionStateValue = 'granted' | 'denied' | 'not_determined';

/**
 * User permission state tracking.
 *
 * Wire format is driven by iOS, which sends one string enum per permission
 * (see `PermissionStateSyncBody` in `client-ios/GearSnitch/Core/Network/APIEndpoint.swift`).
 * All fields are optional because:
 *   - iOS omits fields it does not know about yet (e.g. healthKit until the
 *     user completes the corresponding onboarding step).
 *   - Historical records stored before this field existed may be absent.
 *
 * The API normalizes missing fields to `'not_determined'` on read (see
 * `api/src/utils/permissionsState.ts`).
 */
export interface IPermissionsState {
  bluetooth?: PermissionStateValue;
  location?: PermissionStateValue;
  backgroundLocation?: PermissionStateValue;
  notifications?: PermissionStateValue;
  healthKit?: PermissionStateValue;
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
  nickname?: string | null;
  type: 'earbuds' | 'tracker' | 'belt' | 'bag' | 'other';
  /** BLE peripheral identifier or serial number */
  bluetoothIdentifier: string;
  hardwareModel?: string;
  firmwareVersion?: string;
  status:
    | 'registered'
    | 'active'
    | 'inactive'
    | 'connected'
    | 'monitoring'
    | 'disconnected'
    | 'lost'
    | 'reconnected';
  isFavorite: boolean;
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

// ─── Cycle Tracking ───────────────────────────────────────────────────────

/** Cycle classification */
export type CycleTypeValue = 'peptide' | 'steroid' | 'mixed' | 'other';

/** Cycle lifecycle state */
export type CycleStatusValue =
  | 'planned'
  | 'active'
  | 'paused'
  | 'completed'
  | 'archived';

/** Supported compound categories inside cycle plans and entries */
export type CycleCompoundCategoryValue =
  | 'peptide'
  | 'steroid'
  | 'support'
  | 'pct'
  | 'other';

/** Supported dose units for cycle entries */
export type CycleDoseUnitValue = 'mg' | 'mcg' | 'iu' | 'ml' | 'units';

/** Compound administration routes */
export type CycleRouteValue = 'injection' | 'oral' | 'topical' | 'other';

/** Client that created a cycle entry */
export type CycleEntrySourceValue = 'manual' | 'ios' | 'web' | 'imported';

/** Planned compound definition attached to a cycle */
export interface ICycleCompoundPlan {
  compoundName: string;
  compoundCategory: CycleCompoundCategoryValue;
  targetDose?: number | null;
  doseUnit: CycleDoseUnitValue;
  route?: CycleRouteValue | null;
}

/** Stored cycle object */
export interface ICycle {
  _id: string;
  userId: string;
  name: string;
  type: CycleTypeValue;
  status: CycleStatusValue;
  startDate: string;
  endDate?: string | null;
  timezone: string;
  notes?: string | null;
  tags?: string[];
  compounds?: ICycleCompoundPlan[];
  createdAt: string;
  updatedAt: string;
}

/** Stored cycle entry object */
export interface ICycleEntry {
  _id: string;
  userId: string;
  cycleId: string;
  compoundName: string;
  compoundCategory: CycleCompoundCategoryValue;
  route: CycleRouteValue;
  occurredAt: string;
  dateKey: string;
  plannedDose?: number | null;
  actualDose?: number | null;
  doseUnit: CycleDoseUnitValue;
  notes?: string | null;
  source: CycleEntrySourceValue;
  createdAt: string;
  updatedAt: string;
}

/** Shared pagination shape used by cycle list endpoints */
export interface CyclePagination {
  page: number;
  limit: number;
  total: number;
  totalPages: number;
}

/** Request params for list cycles */
export interface ListCyclesRequest {
  status?: CycleStatusValue;
  type?: CycleTypeValue;
  from?: string;
  to?: string;
  page?: number;
  limit?: number;
}

/** Request params for cycle detail/read operations */
export interface GetCycleRequest {
  id: string;
}

/** Request body for creating a cycle */
export interface CreateCycleRequest {
  name: string;
  type: CycleTypeValue;
  status?: CycleStatusValue;
  startDate: string;
  endDate?: string | null;
  timezone: string;
  notes?: string | null;
  tags?: string[];
  compounds?: ICycleCompoundPlan[];
}

/** Request body for updating a cycle */
export interface UpdateCycleRequest {
  name?: string;
  type?: CycleTypeValue;
  status?: CycleStatusValue;
  startDate?: string;
  endDate?: string | null;
  timezone?: string;
  notes?: string | null;
  tags?: string[];
  compounds?: ICycleCompoundPlan[];
}

/** Response payload for cycle list endpoint */
export interface CycleListResponse {
  cycles: ICycle[];
  pagination: CyclePagination;
}

/** Response payload for cycle detail/create/update endpoints */
export interface CycleResponse {
  cycle: ICycle;
}

/** Response payload for cycle detail endpoint */
export interface CycleDetailResponse extends CycleResponse {}

/** Response payload for cycle create endpoint */
export interface CycleCreateResponse extends CycleResponse {}

/** Response payload for cycle update endpoint */
export interface CycleUpdateResponse extends CycleResponse {}

/** Request params for listing cycle entries */
export interface ListCycleEntriesRequest {
  cycleId: string;
  from?: string;
  to?: string;
  page?: number;
  limit?: number;
}

/** Request body for creating a cycle entry */
export interface CreateCycleEntryRequest {
  cycleId: string;
  compoundName: string;
  compoundCategory: CycleCompoundCategoryValue;
  route: CycleRouteValue;
  occurredAt: string;
  dateKey?: string;
  plannedDose?: number | null;
  actualDose?: number | null;
  doseUnit: CycleDoseUnitValue;
  notes?: string | null;
  source?: CycleEntrySourceValue;
}

/** Request body for updating a cycle entry */
export interface UpdateCycleEntryRequest {
  compoundName?: string;
  compoundCategory?: CycleCompoundCategoryValue;
  route?: CycleRouteValue;
  occurredAt?: string;
  dateKey?: string;
  plannedDose?: number | null;
  actualDose?: number | null;
  doseUnit?: CycleDoseUnitValue;
  notes?: string | null;
  source?: CycleEntrySourceValue;
}

/** Request params for deleting a cycle entry */
export interface DeleteCycleEntryRequest {
  entryId: string;
}

/** Response payload for cycle entry create/update endpoints */
export interface CycleEntryResponse {
  entry: ICycleEntry;
}

/** Response payload for cycle entry list endpoint */
export interface CycleEntryListResponse {
  entries: ICycleEntry[];
  pagination: CyclePagination;
}

/** Response payload for cycle entry create endpoint */
export interface CycleEntryCreateResponse extends CycleEntryResponse {}

/** Response payload for cycle entry update endpoint */
export interface CycleEntryUpdateResponse extends CycleEntryResponse {}

/** Response payload for cycle entry delete endpoint */
export interface CycleEntryDeleteResponse {
  entryId: string;
  deleted: true;
}

/** Per-compound day totals for a cycle summary */
export interface CycleDayCompoundTotal {
  compoundName: string;
  doseUnit: CycleDoseUnitValue;
  entryCount: number;
  totalPlannedDose: number;
  totalActualDose: number;
}

/** Request params for cycle day summary */
export interface CycleDaySummaryRequest {
  date: string;
  cycleId?: string;
}

/** Day summary payload */
export interface CycleDaySummaryResponse {
  date: string;
  timezone: string;
  totalEntries: number;
  activeCycles: number;
  entries: ICycleEntry[];
  compoundTotals: CycleDayCompoundTotal[];
  cycleStatusCounts: Record<CycleStatusValue, number>;
}

/** Per-day activity bucket in month summary */
export interface CycleMonthDayBucket {
  date: string;
  day: number;
  entryCount: number;
  activeCycles: number;
}

/** Request params for cycle month summary */
export interface CycleMonthSummaryRequest {
  year: number;
  month: number;
  cycleId?: string;
}

/** Month summary payload */
export interface CycleMonthSummaryResponse {
  year: number;
  month: number;
  timezone: string;
  days: CycleMonthDayBucket[];
  totals: {
    entryCount: number;
    activeDays: number;
    activeCycles: number;
    cycleCount: number;
  };
}

/** Per-month activity bucket in year summary */
export interface CycleYearMonthBucket {
  month: number;
  entryCount: number;
  activeDays: number;
  activeCycles: number;
  cycleStarts: number;
  cycleEnds: number;
}

/** Top compounds in yearly cycle reporting */
export interface CycleTopCompound {
  compoundName: string;
  entryCount: number;
  totalActualDose?: number | null;
}

/** Request params for cycle year summary */
export interface CycleYearSummaryRequest {
  year: number;
  cycleId?: string;
}

/** Year summary payload */
export interface CycleYearSummaryResponse {
  year: number;
  timezone: string;
  months: CycleYearMonthBucket[];
  totals: {
    entryCount: number;
    activeDays: number;
    activeCycles: number;
    cycleStarts: number;
    cycleEnds: number;
  };
  topCompounds: CycleTopCompound[];
}

/** Supported first-release medication graph categories */
export type MedicationDoseCategoryValue =
  | 'steroid'
  | 'peptide'
  | 'oralMedication';

/** Canonical medication dose amount */
export interface MedicationDoseAmount {
  value: number;
  unit: CycleDoseUnitValue;
}

/** Stored medication dose object */
export interface IMedicationDose {
  _id: string;
  userId: string;
  cycleId?: string | null;
  dateKey: string;
  dayOfYear: number;
  category: MedicationDoseCategoryValue;
  compoundName: string;
  dose: MedicationDoseAmount;
  doseMg?: number | null;
  occurredAt: string;
  notes?: string | null;
  source: CycleEntrySourceValue;
  createdAt: string;
  updatedAt: string;
}

/** Create medication dose request */
export interface CreateMedicationDoseRequest {
  cycleId?: string | null;
  dateKey?: string;
  category: MedicationDoseCategoryValue;
  compoundName: string;
  dose: MedicationDoseAmount;
  occurredAt: string;
  notes?: string | null;
  source?: CycleEntrySourceValue;
}

/** Update medication dose request */
export interface UpdateMedicationDoseRequest {
  cycleId?: string | null;
  dateKey?: string;
  category?: MedicationDoseCategoryValue;
  compoundName?: string;
  dose?: MedicationDoseAmount;
  occurredAt?: string;
  notes?: string | null;
  source?: CycleEntrySourceValue;
}

/** Aggregated medication totals for one day */
export interface MedicationDailySummary {
  dateKey: string;
  entryCount: number;
  totalsMg: {
    steroid: number;
    peptide: number;
    oralMedication: number;
    all: number;
  };
}

/** Additive medication overlay included in calendar responses */
export interface CalendarMedicationOverlay {
  entryCount: number;
  totalDoseMg: number;
  categoryDoseMg: {
    steroid: number;
    peptide: number;
    oralMedication: number;
  };
  hasMedication: boolean;
}

/** Medication graph response for yearly charting */
export interface MedicationYearGraphResponse {
  year: number;
  axis: {
    x: {
      startDay: number;
      endDay: number;
    };
    yMg: {
      min: number;
      max: number;
    };
  };
  series: {
    steroidMgByDay: number[];
    peptideMgByDay: number[];
    oralMedicationMgByDay: number[];
  };
  totalsMg: {
    steroid: number;
    peptide: number;
    oralMedication: number;
    all: number;
  };
}
