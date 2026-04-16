/** Current API version prefix */
export const API_VERSION = 'v1' as const;

/** Number of free days granted for a successful referral */
export const REFERRAL_REWARD_DAYS = 28 as const;

/** Default geofence radius for gyms (meters) */
export const DEFAULT_GYM_RADIUS_METERS = 150 as const;

// ─── Enums as const arrays ─────────────────────────────────────────────────

/** Available user roles */
export const USER_ROLES = ['user', 'admin', 'support'] as const;
export type UserRole = (typeof USER_ROLES)[number];

/** BLE device types */
export const DEVICE_TYPES = [
  'earbuds',
  'tracker',
  'belt',
  'bag',
  'watch',
  'other',
] as const;
export type DeviceType = (typeof DEVICE_TYPES)[number];

/** Device connection statuses */
export const DEVICE_STATUSES = [
  'registered',
  'active',
  'inactive',
  'connected',
  'monitoring',
  'disconnected',
  'lost',
  'reconnected',
] as const;
export type DeviceStatus = (typeof DEVICE_STATUSES)[number];

/** Alert trigger types */
export const ALERT_TYPES = [
  'disconnect_warning',
  'panic_alarm',
  'reconnect_found',
  'gym_entry_activate',
  'gym_exit_deactivate',
] as const;
export type AlertType = (typeof ALERT_TYPES)[number];

/** Alert severity levels */
export const ALERT_SEVERITIES = ['low', 'medium', 'high', 'critical'] as const;
export type AlertSeverity = (typeof ALERT_SEVERITIES)[number];

/** Meal type options */
export const MEAL_TYPES = [
  'breakfast',
  'lunch',
  'dinner',
  'snack',
] as const;
export type MealType = (typeof MEAL_TYPES)[number];

/** Health metric type identifiers */
export const METRIC_TYPES = [
  'weight',
  'height',
  'body_fat',
  'bmi',
  'resting_heart_rate',
  'heart_rate',
  'blood_pressure_systolic',
  'blood_pressure_diastolic',
  'steps',
  'active_calories',
  'workout_session',
] as const;
export type MetricType = (typeof METRIC_TYPES)[number];

/** Order lifecycle statuses */
export const ORDER_STATUSES = [
  'pending',
  'paid',
  'processing',
  'shipped',
  'delivered',
  'cancelled',
  'refunded',
] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

/** Subscription lifecycle statuses */
export const SUBSCRIPTION_STATUSES = [
  'active',
  'expired',
  'grace_period',
  'cancelled',
] as const;
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];
