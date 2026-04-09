import { z } from 'zod';

// ─── Auth ──────────────────────────────────────────────────────────────────

/** Apple Sign-In token exchange */
export const loginAppleSchema = z.object({
  identityToken: z.string().min(1, 'Identity token is required'),
  authorizationCode: z.string().min(1, 'Authorization code is required'),
  fullName: z
    .object({
      givenName: z.string().optional(),
      familyName: z.string().optional(),
    })
    .optional(),
  referralCode: z.string().max(32).optional(),
});
export type LoginAppleInput = z.infer<typeof loginAppleSchema>;

/** Google Sign-In token exchange */
export const loginGoogleSchema = z.object({
  idToken: z.string().min(1, 'ID token is required'),
  referralCode: z.string().max(32).optional(),
});
export type LoginGoogleInput = z.infer<typeof loginGoogleSchema>;

// ─── User ──────────────────────────────────────────────────────────────────

/** Update user profile fields */
export const updateUserSchema = z.object({
  displayName: z.string().min(1).max(100).optional(),
  photoUrl: z.string().url().optional(),
  defaultGymId: z.string().optional(),
});
export type UpdateUserInput = z.infer<typeof updateUserSchema>;

/** Update user preferences */
export const updatePreferencesSchema = z.object({
  units: z.enum(['imperial', 'metric']).optional(),
  theme: z.enum(['dark', 'light', 'system']).optional(),
  disconnectAlertDelay: z.number().int().min(0).max(600).optional(),
  panicAlertEnabled: z.boolean().optional(),
});
export type UpdatePreferencesInput = z.infer<typeof updatePreferencesSchema>;

// ─── Device ────────────────────────────────────────────────────────────────

/** Register a new BLE device */
export const createDeviceSchema = z.object({
  name: z.string().min(1).max(100),
  type: z.enum(['earbuds', 'tracker', 'belt', 'bag', 'other']),
  identifier: z.string().min(1).max(255),
  hardwareModel: z.string().max(100).optional(),
  firmwareVersion: z.string().max(50).optional(),
});
export type CreateDeviceInput = z.infer<typeof createDeviceSchema>;

/** Update an existing device */
export const updateDeviceSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  type: z.enum(['earbuds', 'tracker', 'belt', 'bag', 'other']).optional(),
  hardwareModel: z.string().max(100).optional(),
  firmwareVersion: z.string().max(50).optional(),
  monitoringEnabled: z.boolean().optional(),
});
export type UpdateDeviceInput = z.infer<typeof updateDeviceSchema>;

/** Update device connection status (from mobile client) */
export const deviceStatusSchema = z.object({
  status: z.enum([
    'registered',
    'active',
    'inactive',
    'connected',
    'disconnected',
    'lost',
    'reconnected',
  ]),
  lastSeenLocation: z
    .object({
      type: z.literal('Point'),
      coordinates: z.tuple([z.number(), z.number()]),
    })
    .optional(),
  lastSignalStrength: z.number().int().min(-150).max(0).optional(),
});
export type DeviceStatusInput = z.infer<typeof deviceStatusSchema>;

// ─── Gym ───────────────────────────────────────────────────────────────────

/** Create a new gym geofence */
export const createGymSchema = z.object({
  name: z.string().min(1).max(100),
  isDefault: z.boolean().optional().default(false),
  location: z.object({
    type: z.literal('Point'),
    coordinates: z.tuple([z.number(), z.number()]),
  }),
  radiusMeters: z.number().int().min(25).max(1000).optional().default(150),
});
export type CreateGymInput = z.infer<typeof createGymSchema>;

/** Update an existing gym */
export const updateGymSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  isDefault: z.boolean().optional(),
  location: z
    .object({
      type: z.literal('Point'),
      coordinates: z.tuple([z.number(), z.number()]),
    })
    .optional(),
  radiusMeters: z.number().int().min(25).max(1000).optional(),
});
export type UpdateGymInput = z.infer<typeof updateGymSchema>;

// ─── Nutrition ─────────────────────────────────────────────────────────────

/** Log a meal */
export const createMealSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD'),
  mealType: z.enum(['breakfast', 'lunch', 'dinner', 'snack']),
  name: z.string().min(1).max(200),
  calories: z.number().min(0),
  protein: z.number().min(0),
  carbs: z.number().min(0),
  fat: z.number().min(0),
  fiber: z.number().min(0).optional(),
  sugar: z.number().min(0).optional(),
});
export type CreateMealInput = z.infer<typeof createMealSchema>;

/** Update a meal entry */
export const updateMealSchema = z.object({
  mealType: z.enum(['breakfast', 'lunch', 'dinner', 'snack']).optional(),
  name: z.string().min(1).max(200).optional(),
  calories: z.number().min(0).optional(),
  protein: z.number().min(0).optional(),
  carbs: z.number().min(0).optional(),
  fat: z.number().min(0).optional(),
  fiber: z.number().min(0).optional(),
  sugar: z.number().min(0).optional(),
});
export type UpdateMealInput = z.infer<typeof updateMealSchema>;

// ─── Workout ───────────────────────────────────────────────────────────────

/** Create a new workout session */
export const createWorkoutSchema = z.object({
  gymId: z.string().optional(),
  name: z.string().min(1).max(200),
  startedAt: z.string().datetime(),
  endedAt: z.string().datetime().optional(),
  durationMinutes: z.number().int().min(0).optional(),
  notes: z.string().max(2000).optional(),
  source: z.string().max(100).optional(),
});
export type CreateWorkoutInput = z.infer<typeof createWorkoutSchema>;

/** Add an exercise to an existing workout */
export const addExerciseSchema = z.object({
  name: z.string().min(1).max(200),
  sets: z
    .array(
      z.object({
        reps: z.number().int().min(0).optional(),
        weight: z.number().min(0).optional(),
        durationSeconds: z.number().int().min(0).optional(),
      })
    )
    .min(1),
});
export type AddExerciseInput = z.infer<typeof addExerciseSchema>;

// ─── Water ─────────────────────────────────────────────────────────────────

/** Log water intake */
export const waterLogSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD'),
  amountMl: z.number().int().min(1).max(10000),
});
export type WaterLogInput = z.infer<typeof waterLogSchema>;

// ─── Emergency Contact ─────────────────────────────────────────────────────

/** Create an emergency contact */
export const createEmergencyContactSchema = z.object({
  name: z.string().min(1).max(100),
  phone: z.string().min(7).max(20),
  email: z.string().email().optional(),
  notifyOnPanic: z.boolean().optional().default(true),
  notifyOnDisconnect: z.boolean().optional().default(false),
});
export type CreateEmergencyContactInput = z.infer<
  typeof createEmergencyContactSchema
>;
