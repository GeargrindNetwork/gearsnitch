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
  nickname: z.string().trim().min(1).max(100).nullable().optional(),
  type: z.enum(['earbuds', 'tracker', 'belt', 'bag', 'watch', 'other']),
  bluetoothIdentifier: z.string().min(1).max(255),
  isFavorite: z.boolean().optional(),
  hardwareModel: z.string().max(100).optional(),
  firmwareVersion: z.string().max(50).optional(),
});
export type CreateDeviceInput = z.infer<typeof createDeviceSchema>;

/** Update an existing device */
export const updateDeviceSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  nickname: z.string().trim().min(1).max(100).nullable().optional(),
  type: z.enum(['earbuds', 'tracker', 'belt', 'bag', 'watch', 'other']).optional(),
  hardwareModel: z.string().max(100).optional(),
  firmwareVersion: z.string().max(50).optional(),
  isFavorite: z.boolean().optional(),
});
export type UpdateDeviceInput = z.infer<typeof updateDeviceSchema>;

/** Update device connection status (from mobile client) */
export const deviceStatusSchema = z.object({
  status: z.enum([
    'registered',
    'active',
    'inactive',
    'connected',
    'monitoring',
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

// ─── Cycle Tracking ───────────────────────────────────────────────────────

const cycleDateKeySchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD');

/** Cycle domain type */
export const cycleTypeSchema = z.enum(['peptide', 'steroid', 'mixed', 'other']);
export type CycleTypeInput = z.infer<typeof cycleTypeSchema>;

/** Cycle lifecycle state */
export const cycleStatusSchema = z.enum([
  'planned',
  'active',
  'paused',
  'completed',
  'archived',
]);
export type CycleStatusInput = z.infer<typeof cycleStatusSchema>;

/** Compound category for planned compounds and logged entries */
export const cycleCompoundCategorySchema = z.enum([
  'peptide',
  'steroid',
  'support',
  'pct',
  'other',
]);
export type CycleCompoundCategoryInput = z.infer<
  typeof cycleCompoundCategorySchema
>;

/** Dose units supported for cycle compounds and entries */
export const cycleDoseUnitSchema = z.enum(['mg', 'mcg', 'iu', 'ml', 'units']);
export type CycleDoseUnitInput = z.infer<typeof cycleDoseUnitSchema>;

/** Compound administration route */
export const cycleRouteSchema = z.enum([
  'injection',
  'oral',
  'topical',
  'other',
]);
export type CycleRouteInput = z.infer<typeof cycleRouteSchema>;

/** Entry source channel */
export const cycleEntrySourceSchema = z.enum([
  'manual',
  'ios',
  'web',
  'imported',
]);
export type CycleEntrySourceInput = z.infer<typeof cycleEntrySourceSchema>;

/** Planned compound attached to a cycle */
export const cycleCompoundSchema = z.object({
  compoundName: z.string().trim().min(1).max(120),
  compoundCategory: cycleCompoundCategorySchema,
  targetDose: z.number().min(0).nullable().optional(),
  doseUnit: cycleDoseUnitSchema,
  route: cycleRouteSchema.nullable().optional(),
});
export type CycleCompoundInput = z.infer<typeof cycleCompoundSchema>;

/** Full cycle object payload */
export const cycleSchema = z.object({
  _id: z.string().min(1),
  userId: z.string().min(1),
  name: z.string().trim().min(1).max(120),
  type: cycleTypeSchema,
  status: cycleStatusSchema,
  startDate: cycleDateKeySchema,
  endDate: cycleDateKeySchema.nullable().optional(),
  timezone: z.string().min(1).max(100),
  notes: z.string().max(2000).nullable().optional(),
  tags: z.array(z.string().trim().min(1).max(64)).max(20).optional(),
  compounds: z.array(cycleCompoundSchema).optional(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});
export type CyclePayload = z.infer<typeof cycleSchema>;

/** Full cycle entry object payload */
export const cycleEntrySchema = z.object({
  _id: z.string().min(1),
  userId: z.string().min(1),
  cycleId: z.string().min(1),
  compoundName: z.string().trim().min(1).max(120),
  compoundCategory: cycleCompoundCategorySchema,
  route: cycleRouteSchema,
  occurredAt: z.string().datetime(),
  dateKey: cycleDateKeySchema,
  plannedDose: z.number().min(0).nullable().optional(),
  actualDose: z.number().min(0).nullable().optional(),
  doseUnit: cycleDoseUnitSchema,
  notes: z.string().max(2000).nullable().optional(),
  source: cycleEntrySourceSchema,
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});
export type CycleEntryPayload = z.infer<typeof cycleEntrySchema>;

/** Route params for cycle detail/update/delete */
export const cycleIdParamsSchema = z.object({
  id: z.string().min(1),
});
export type CycleIdParamsInput = z.infer<typeof cycleIdParamsSchema>;

/** Route params for entry update/delete */
export const cycleEntryIdParamsSchema = z.object({
  entryId: z.string().min(1),
});
export type CycleEntryIdParamsInput = z.infer<typeof cycleEntryIdParamsSchema>;

/** Query params for cycle list endpoint */
export const listCyclesQuerySchema = z.object({
  status: cycleStatusSchema.optional(),
  type: cycleTypeSchema.optional(),
  from: cycleDateKeySchema.optional(),
  to: cycleDateKeySchema.optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
});
export type ListCyclesQueryInput = z.infer<typeof listCyclesQuerySchema>;

/** Request body for creating a cycle */
export const createCycleSchema = z.object({
  name: z.string().trim().min(1).max(120),
  type: cycleTypeSchema,
  status: cycleStatusSchema.optional(),
  startDate: cycleDateKeySchema,
  endDate: cycleDateKeySchema.nullable().optional(),
  timezone: z.string().min(1).max(100),
  notes: z.string().max(2000).nullable().optional(),
  tags: z.array(z.string().trim().min(1).max(64)).max(20).optional(),
  compounds: z.array(cycleCompoundSchema).optional(),
});
export type CreateCycleInput = z.infer<typeof createCycleSchema>;

/** Request body for updating a cycle */
export const updateCycleSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  type: cycleTypeSchema.optional(),
  status: cycleStatusSchema.optional(),
  startDate: cycleDateKeySchema.optional(),
  endDate: cycleDateKeySchema.nullable().optional(),
  timezone: z.string().min(1).max(100).optional(),
  notes: z.string().max(2000).nullable().optional(),
  tags: z.array(z.string().trim().min(1).max(64)).max(20).optional(),
  compounds: z.array(cycleCompoundSchema).optional(),
});
export type UpdateCycleInput = z.infer<typeof updateCycleSchema>;

/** Query params for cycle entry list endpoint */
export const listCycleEntriesQuerySchema = z.object({
  from: cycleDateKeySchema.optional(),
  to: cycleDateKeySchema.optional(),
  page: z.coerce.number().int().min(1).optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
});
export type ListCycleEntriesQueryInput = z.infer<
  typeof listCycleEntriesQuerySchema
>;

/** Request body for creating a cycle entry */
export const createCycleEntrySchema = z.object({
  cycleId: z.string().min(1),
  compoundName: z.string().trim().min(1).max(120),
  compoundCategory: cycleCompoundCategorySchema,
  route: cycleRouteSchema,
  occurredAt: z.string().datetime(),
  dateKey: cycleDateKeySchema.optional(),
  plannedDose: z.number().min(0).nullable().optional(),
  actualDose: z.number().min(0).nullable().optional(),
  doseUnit: cycleDoseUnitSchema,
  notes: z.string().max(2000).nullable().optional(),
  source: cycleEntrySourceSchema.optional(),
});
export type CreateCycleEntryInput = z.infer<typeof createCycleEntrySchema>;

/** Request body for updating a cycle entry */
export const updateCycleEntrySchema = z.object({
  compoundName: z.string().trim().min(1).max(120).optional(),
  compoundCategory: cycleCompoundCategorySchema.optional(),
  route: cycleRouteSchema.optional(),
  occurredAt: z.string().datetime().optional(),
  dateKey: cycleDateKeySchema.optional(),
  plannedDose: z.number().min(0).nullable().optional(),
  actualDose: z.number().min(0).nullable().optional(),
  doseUnit: cycleDoseUnitSchema.optional(),
  notes: z.string().max(2000).nullable().optional(),
  source: cycleEntrySourceSchema.optional(),
});
export type UpdateCycleEntryInput = z.infer<typeof updateCycleEntrySchema>;

/** Request shape for deleting an entry */
export const deleteCycleEntrySchema = cycleEntryIdParamsSchema;
export type DeleteCycleEntryInput = z.infer<typeof deleteCycleEntrySchema>;

/** Common pagination payload used by list responses */
export const cyclePaginationSchema = z.object({
  page: z.number().int().min(1),
  limit: z.number().int().min(1),
  total: z.number().int().min(0),
  totalPages: z.number().int().min(0),
});
export type CyclePaginationPayload = z.infer<typeof cyclePaginationSchema>;

/** List cycles response payload */
export const cycleListResponseSchema = z.object({
  cycles: z.array(cycleSchema),
  pagination: cyclePaginationSchema,
});
export type CycleListResponsePayload = z.infer<typeof cycleListResponseSchema>;

/** Single-cycle response payload for detail/create/update */
export const cycleResponseSchema = z.object({
  cycle: cycleSchema,
});
export type CycleResponsePayload = z.infer<typeof cycleResponseSchema>;

/** List entries response payload */
export const cycleEntryListResponseSchema = z.object({
  entries: z.array(cycleEntrySchema),
  pagination: cyclePaginationSchema,
});
export type CycleEntryListResponsePayload = z.infer<
  typeof cycleEntryListResponseSchema
>;

/** Single-entry response payload for create/update */
export const cycleEntryResponseSchema = z.object({
  entry: cycleEntrySchema,
});
export type CycleEntryResponsePayload = z.infer<typeof cycleEntryResponseSchema>;

/** Entry deletion response payload */
export const cycleEntryDeleteResponseSchema = z.object({
  entryId: z.string().min(1),
  deleted: z.literal(true),
});
export type CycleEntryDeleteResponsePayload = z.infer<
  typeof cycleEntryDeleteResponseSchema
>;

/** Query params for cycle day summary endpoint */
export const cycleDaySummaryQuerySchema = z.object({
  date: cycleDateKeySchema,
  cycleId: z.string().min(1).optional(),
});
export type CycleDaySummaryQueryInput = z.infer<
  typeof cycleDaySummaryQuerySchema
>;

/** Query params for cycle month summary endpoint */
export const cycleMonthSummaryQuerySchema = z.object({
  year: z.coerce.number().int().min(1970).max(9999),
  month: z.coerce.number().int().min(1).max(12),
  cycleId: z.string().min(1).optional(),
});
export type CycleMonthSummaryQueryInput = z.infer<
  typeof cycleMonthSummaryQuerySchema
>;

/** Query params for cycle year summary endpoint */
export const cycleYearSummaryQuerySchema = z.object({
  year: z.coerce.number().int().min(1970).max(9999),
  cycleId: z.string().min(1).optional(),
});
export type CycleYearSummaryQueryInput = z.infer<
  typeof cycleYearSummaryQuerySchema
>;

/** Daily per-compound aggregate for cycle reporting */
export const cycleDayCompoundTotalSchema = z.object({
  compoundName: z.string().min(1),
  doseUnit: cycleDoseUnitSchema,
  entryCount: z.number().int().min(0),
  totalPlannedDose: z.number().min(0),
  totalActualDose: z.number().min(0),
});
export type CycleDayCompoundTotalPayload = z.infer<
  typeof cycleDayCompoundTotalSchema
>;

/** Day summary payload */
export const cycleDaySummaryResponseSchema = z.object({
  date: cycleDateKeySchema,
  timezone: z.string().min(1),
  totalEntries: z.number().int().min(0),
  activeCycles: z.number().int().min(0),
  entries: z.array(cycleEntrySchema),
  compoundTotals: z.array(cycleDayCompoundTotalSchema),
  cycleStatusCounts: z.object({
    planned: z.number().int().min(0),
    active: z.number().int().min(0),
    paused: z.number().int().min(0),
    completed: z.number().int().min(0),
    archived: z.number().int().min(0),
  }),
});
export type CycleDaySummaryResponsePayload = z.infer<
  typeof cycleDaySummaryResponseSchema
>;

/** Per-day bucket for month summary */
export const cycleMonthDayBucketSchema = z.object({
  date: cycleDateKeySchema,
  day: z.number().int().min(1).max(31),
  entryCount: z.number().int().min(0),
  activeCycles: z.number().int().min(0),
});
export type CycleMonthDayBucketPayload = z.infer<
  typeof cycleMonthDayBucketSchema
>;

/** Month summary payload */
export const cycleMonthSummaryResponseSchema = z.object({
  year: z.number().int().min(1970).max(9999),
  month: z.number().int().min(1).max(12),
  timezone: z.string().min(1),
  days: z.array(cycleMonthDayBucketSchema),
  totals: z.object({
    entryCount: z.number().int().min(0),
    activeDays: z.number().int().min(0),
    activeCycles: z.number().int().min(0),
    cycleCount: z.number().int().min(0),
  }),
});
export type CycleMonthSummaryResponsePayload = z.infer<
  typeof cycleMonthSummaryResponseSchema
>;

/** Per-month bucket for year summary */
export const cycleYearMonthBucketSchema = z.object({
  month: z.number().int().min(1).max(12),
  entryCount: z.number().int().min(0),
  activeDays: z.number().int().min(0),
  activeCycles: z.number().int().min(0),
  cycleStarts: z.number().int().min(0),
  cycleEnds: z.number().int().min(0),
});
export type CycleYearMonthBucketPayload = z.infer<
  typeof cycleYearMonthBucketSchema
>;

/** Most frequent compounds for a year summary */
export const cycleTopCompoundSchema = z.object({
  compoundName: z.string().min(1),
  entryCount: z.number().int().min(0),
  totalActualDose: z.number().min(0).nullable().optional(),
});
export type CycleTopCompoundPayload = z.infer<typeof cycleTopCompoundSchema>;

/** Year summary payload */
export const cycleYearSummaryResponseSchema = z.object({
  year: z.number().int().min(1970).max(9999),
  timezone: z.string().min(1),
  months: z.array(cycleYearMonthBucketSchema).length(12),
  totals: z.object({
    entryCount: z.number().int().min(0),
    activeDays: z.number().int().min(0),
    activeCycles: z.number().int().min(0),
    cycleStarts: z.number().int().min(0),
    cycleEnds: z.number().int().min(0),
  }),
  topCompounds: z.array(cycleTopCompoundSchema),
});
export type CycleYearSummaryResponsePayload = z.infer<
  typeof cycleYearSummaryResponseSchema
>;

// ─── Medication Tracking ───────────────────────────────────────────────────

/** First-release medication categories shown in graphing and calendar overlays */
export const medicationDoseCategorySchema = z.enum([
  'steroid',
  'peptide',
  'oralMedication',
]);
export type MedicationDoseCategoryInput = z.infer<
  typeof medicationDoseCategorySchema
>;

/** Canonical nested dose payload */
export const medicationDoseAmountSchema = z.object({
  value: z.number().min(0),
  unit: cycleDoseUnitSchema,
});
export type MedicationDoseAmountPayload = z.infer<
  typeof medicationDoseAmountSchema
>;

/** Stored medication dose object */
export const medicationDoseSchema = z.object({
  _id: z.string().min(1),
  userId: z.string().min(1),
  cycleId: z.string().min(1).nullable().optional(),
  dateKey: cycleDateKeySchema,
  dayOfYear: z.number().int().min(1).max(366),
  category: medicationDoseCategorySchema,
  compoundName: z.string().trim().min(1).max(120),
  dose: medicationDoseAmountSchema,
  doseMg: z.number().min(0).nullable().optional(),
  occurredAt: z.string().datetime(),
  notes: z.string().max(2000).nullable().optional(),
  source: cycleEntrySourceSchema,
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});
export type MedicationDosePayload = z.infer<typeof medicationDoseSchema>;

/** Create medication dose request */
export const createMedicationDoseSchema = z.object({
  cycleId: z.string().min(1).nullable().optional(),
  dateKey: cycleDateKeySchema.optional(),
  category: medicationDoseCategorySchema,
  compoundName: z.string().trim().min(1).max(120),
  dose: medicationDoseAmountSchema,
  occurredAt: z.string().datetime(),
  notes: z.string().max(2000).nullable().optional(),
  source: cycleEntrySourceSchema.optional(),
});
export type CreateMedicationDoseInput = z.infer<
  typeof createMedicationDoseSchema
>;

/** Update medication dose request */
export const updateMedicationDoseSchema = z.object({
  cycleId: z.string().min(1).nullable().optional(),
  dateKey: cycleDateKeySchema.optional(),
  category: medicationDoseCategorySchema.optional(),
  compoundName: z.string().trim().min(1).max(120).optional(),
  dose: medicationDoseAmountSchema.optional(),
  occurredAt: z.string().datetime().optional(),
  notes: z.string().max(2000).nullable().optional(),
  source: cycleEntrySourceSchema.optional(),
});
export type UpdateMedicationDoseInput = z.infer<
  typeof updateMedicationDoseSchema
>;

/** Medication day totals */
export const medicationDailySummarySchema = z.object({
  dateKey: cycleDateKeySchema,
  entryCount: z.number().int().min(0),
  totalsMg: z.object({
    steroid: z.number().min(0),
    peptide: z.number().min(0),
    oralMedication: z.number().min(0),
    all: z.number().min(0),
  }),
});
export type MedicationDailySummaryPayload = z.infer<
  typeof medicationDailySummarySchema
>;

/** Calendar overlay medication block */
export const calendarMedicationOverlaySchema = z.object({
  entryCount: z.number().int().min(0),
  totalDoseMg: z.number().min(0),
  categoryDoseMg: z.object({
    steroid: z.number().min(0),
    peptide: z.number().min(0),
    oralMedication: z.number().min(0),
  }),
  hasMedication: z.boolean(),
});
export type CalendarMedicationOverlayPayload = z.infer<
  typeof calendarMedicationOverlaySchema
>;

/** Year graph response for 365/366-day medication charting */
export const medicationYearGraphResponseSchema = z.object({
  year: z.number().int().min(1970).max(9999),
  axis: z.object({
    x: z.object({
      startDay: z.number().int().min(1).max(366),
      endDay: z.number().int().min(1).max(366),
    }),
    yMg: z.object({
      min: z.number().min(0),
      max: z.number().min(0),
    }),
  }),
  series: z.object({
    steroidMgByDay: z.array(z.number().min(0)),
    peptideMgByDay: z.array(z.number().min(0)),
    oralMedicationMgByDay: z.array(z.number().min(0)),
  }),
  totalsMg: z.object({
    steroid: z.number().min(0),
    peptide: z.number().min(0),
    oralMedication: z.number().min(0),
    all: z.number().min(0),
  }),
});
export type MedicationYearGraphResponsePayload = z.infer<
  typeof medicationYearGraphResponseSchema
>;

// ─── Heart Rate ─────────────────────────────────────────────────────────────

/** Single heart rate sample from AirPods Pro 3 or other HealthKit source */
export const heartRateSampleSchema = z.object({
  bpm: z.number().int().min(30).max(250),
  recordedAt: z.string().datetime(),
  source: z.string().max(120).optional().default('airpods_pro'),
});
export type HeartRateSampleInput = z.infer<typeof heartRateSampleSchema>;

/** Batch heart rate ingestion request */
export const heartRateBatchSchema = z.object({
  samples: z.array(heartRateSampleSchema).min(1).max(500),
  sessionId: z.string().optional(),
});
export type HeartRateBatchInput = z.infer<typeof heartRateBatchSchema>;

/** Heart rate zone distribution as percentages (0-100) */
export const heartRateZoneDistributionSchema = z.object({
  rest: z.number().min(0).max(100),
  light: z.number().min(0).max(100),
  fatBurn: z.number().min(0).max(100),
  cardio: z.number().min(0).max(100),
  peak: z.number().min(0).max(100),
});
export type HeartRateZoneDistribution = z.infer<typeof heartRateZoneDistributionSchema>;

/** Session heart rate summary with min/max/avg and zone breakdown */
export const heartRateSessionSummarySchema = z.object({
  sessionId: z.string().nullable().optional(),
  from: z.string().datetime(),
  to: z.string().datetime(),
  sampleCount: z.number().int().min(0),
  minBPM: z.number().int().min(0),
  maxBPM: z.number().int().min(0),
  avgBPM: z.number().min(0),
  zoneDistribution: heartRateZoneDistributionSchema,
});
export type HeartRateSessionSummary = z.infer<typeof heartRateSessionSummarySchema>;

// ─── Health Dashboard ──────────────────────────────────────────────────────

/** Latest heart rate reading */
export const healthDashboardLatestHRSchema = z.object({
  bpm: z.number().int().min(0),
  recordedAt: z.string().datetime(),
  source: z.string(),
});
export type HealthDashboardLatestHR = z.infer<typeof healthDashboardLatestHRSchema>;

/** Today's heart rate aggregate */
export const healthDashboardTodayHRSchema = z.object({
  sampleCount: z.number().int().min(0),
  minBPM: z.number().int().min(0),
  maxBPM: z.number().int().min(0),
  avgBPM: z.number().min(0),
  zoneDistribution: heartRateZoneDistributionSchema,
});
export type HealthDashboardTodayHR = z.infer<typeof healthDashboardTodayHRSchema>;

/** Session entry in health dashboard */
export const healthDashboardSessionSchema = z.object({
  _id: z.string(),
  gymName: z.string(),
  startedAt: z.string().datetime(),
  endedAt: z.string().datetime().nullable(),
  durationMinutes: z.number().nullable(),
  heartRateSummary: heartRateSessionSummarySchema.nullable(),
});
export type HealthDashboardSession = z.infer<typeof healthDashboardSessionSchema>;

/** Device entry in health dashboard */
export const healthDashboardDeviceSchema = z.object({
  _id: z.string(),
  name: z.string(),
  nickname: z.string().nullable(),
  type: z.string(),
  status: z.string(),
  isFavorite: z.boolean(),
  lastSeenAt: z.string().datetime().nullable(),
  healthCapable: z.boolean(),
});
export type HealthDashboardDevice = z.infer<typeof healthDashboardDeviceSchema>;

/** Health data source attribution */
export const healthDashboardSourceSchema = z.object({
  name: z.string(),
  type: z.enum(['airpods_pro', 'apple_watch', 'apple_health', 'manual']),
  lastDataAt: z.string().datetime().nullable(),
  sampleCountToday: z.number().int().min(0),
});
export type HealthDashboardSource = z.infer<typeof healthDashboardSourceSchema>;

/** Full health dashboard response */
export const healthDashboardResponseSchema = z.object({
  heartRate: z.object({
    latest: healthDashboardLatestHRSchema.nullable(),
    today: healthDashboardTodayHRSchema.nullable(),
  }),
  sessions: z.object({
    today: z.array(healthDashboardSessionSchema),
    activeSession: z.object({
      _id: z.string(),
      gymName: z.string(),
      startedAt: z.string().datetime(),
    }).nullable(),
  }),
  devices: z.array(healthDashboardDeviceSchema),
  sources: z.array(healthDashboardSourceSchema),
});
export type HealthDashboardResponse = z.infer<typeof healthDashboardResponseSchema>;

// ─── Health Trends ─────────────────────────────────────────────────────────

export const healthTrendsHRPointSchema = z.object({
  date: z.string().datetime(),
  bpm: z.number().int(),
  zone: z.string(),
});

export const healthTrendsDailyPointSchema = z.object({
  date: z.string().datetime(),
  value: z.number(),
});

export const healthTrendsWeightPointSchema = z.object({
  date: z.string().datetime(),
  value: z.number(),
  unit: z.string(),
});

export const healthTrendsWorkoutPointSchema = z.object({
  date: z.string().datetime(),
  count: z.number().int(),
  durationMinutes: z.number(),
});

export const healthTrendsResponseSchema = z.object({
  days: z.number().int(),
  since: z.string().datetime(),
  heartRateScatter: z.array(healthTrendsHRPointSchema),
  restingHeartRate: z.array(healthTrendsDailyPointSchema),
  weightTrend: z.array(healthTrendsWeightPointSchema),
  caloriesTrend: z.array(healthTrendsDailyPointSchema),
  workoutTrend: z.array(healthTrendsWorkoutPointSchema),
});
export type HealthTrendsResponse = z.infer<typeof healthTrendsResponseSchema>;
