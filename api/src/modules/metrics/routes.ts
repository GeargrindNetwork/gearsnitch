import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { Workout } from '../../models/Workout.js';
import { Run } from '../../models/Run.js';
import { Meal } from '../../models/Meal.js';
import { HealthMetric } from '../../models/HealthMetric.js';
import { successResponse, errorResponse } from '../../utils/response.js';

/**
 * Backlog item #20 — Dashboard trend charts (week / month / year).
 *
 * Returns bucketed summaries pulled from the existing Workout / Run / Meal /
 * HealthMetric collections. The buckets are generated up-front so charts
 * always receive a dense time-series (no gaps on days with zero activity).
 *
 * Bucket granularity:
 *   - week  → 7 daily buckets (rolling 7 days)
 *   - month → 30 daily buckets (rolling 30 days)
 *   - year  → 12 monthly buckets (rolling 12 months)
 */

export type TrendRange = 'week' | 'month' | 'year';

export interface TrendBucket {
  ts: string;
  workouts: number;
  workoutMinutes: number;
  runs: number;
  runMeters: number;
  calories: number;
  weightKg: number | null;
}

export interface TrendResponse {
  range: TrendRange;
  timezone: string;
  buckets: TrendBucket[];
  summary: {
    totalWorkouts: number;
    totalRuns: number;
    totalCalories: number;
    avgWorkoutsPerWeek: number;
  };
}

const SUPPORTED_RANGES: ReadonlyArray<TrendRange> = ['week', 'month', 'year'];

function isSupportedRange(value: unknown): value is TrendRange {
  return typeof value === 'string' && (SUPPORTED_RANGES as ReadonlyArray<string>).includes(value);
}

/**
 * Permissive timezone validator. We accept IANA tz names (containing `/`) and
 * the special values `UTC`/`GMT`. If the client sends garbage we fall back to
 * UTC so a mis-configured browser never breaks the dashboard.
 */
export function sanitizeTimezone(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 64) {
    return 'UTC';
  }
  if (!/^[A-Za-z_\-/+0-9]+$/.test(value)) {
    return 'UTC';
  }
  return value;
}

/**
 * Build the bucket plan (start timestamps + granularity) for a range. Pure —
 * no DB / timezone library dependency, so it's cheap to unit-test.
 *
 *   - week  → 7 daily buckets, starting 6 days ago @ UTC midnight
 *   - month → 30 daily buckets, starting 29 days ago @ UTC midnight
 *   - year  → 12 monthly buckets, starting 11 months ago @ UTC start-of-month
 */
export function buildBucketPlan(
  range: TrendRange,
  now: Date,
): { starts: Date[]; granularity: 'day' | 'month' } {
  const starts: Date[] = [];

  if (range === 'year') {
    const base = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    for (let i = 11; i >= 0; i -= 1) {
      const d = new Date(base);
      d.setUTCMonth(d.getUTCMonth() - i);
      starts.push(d);
    }
    return { starts, granularity: 'month' };
  }

  const totalDays = range === 'week' ? 7 : 30;
  const base = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  for (let i = totalDays - 1; i >= 0; i -= 1) {
    const d = new Date(base);
    d.setUTCDate(d.getUTCDate() - i);
    starts.push(d);
  }

  return { starts, granularity: 'day' };
}

/**
 * Return the bucket-start Date that a given event timestamp falls into, or
 * `null` if the event is outside the plan window. Pure function — lives next
 * to `buildBucketPlan` so both tables are trivially testable.
 */
export function resolveBucketStart(
  eventAt: Date,
  plan: { starts: Date[]; granularity: 'day' | 'month' },
): Date | null {
  if (plan.starts.length === 0) {
    return null;
  }

  const eventMs = eventAt.getTime();
  const first = plan.starts[0]!;
  const last = plan.starts[plan.starts.length - 1]!;

  if (eventMs < first.getTime()) {
    return null;
  }

  if (plan.granularity === 'day') {
    const windowEnd = new Date(last);
    windowEnd.setUTCDate(windowEnd.getUTCDate() + 1);
    if (eventMs >= windowEnd.getTime()) {
      return null;
    }
    const dayStart = new Date(Date.UTC(
      eventAt.getUTCFullYear(),
      eventAt.getUTCMonth(),
      eventAt.getUTCDate(),
    ));
    return dayStart;
  }

  // granularity === 'month'
  const windowEnd = new Date(last);
  windowEnd.setUTCMonth(windowEnd.getUTCMonth() + 1);
  if (eventMs >= windowEnd.getTime()) {
    return null;
  }
  return new Date(Date.UTC(eventAt.getUTCFullYear(), eventAt.getUTCMonth(), 1));
}

/**
 * Resolve the YYYY-MM-DD date key used by Meal.date into its bucket start.
 * Meal.date is stored as a `YYYY-MM-DD` string (see models/Meal.ts), so we
 * parse it as a UTC midnight Date before running it through the normal
 * bucket resolver.
 */
export function resolveBucketStartFromDateKey(
  dateKey: string,
  plan: { starts: Date[]; granularity: 'day' | 'month' },
): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) {
    return null;
  }
  const [y, m, d] = dateKey.split('-').map((n) => Number.parseInt(n, 10));
  const asDate = new Date(Date.UTC(y!, (m! - 1), d!));
  return resolveBucketStart(asDate, plan);
}

/**
 * Compose the final bucket array from the plan + raw event rows. Pure. All
 * time-series charts are built off this output, so unit tests cover both
 * empty-data fallback and end-to-end bucket math.
 */
export function composeBuckets(
  plan: { starts: Date[]; granularity: 'day' | 'month' },
  rows: {
    workouts: Array<{ startedAt: Date; durationMinutes: number }>;
    runs: Array<{ startedAt: Date; distanceMeters: number }>;
    meals: Array<{ dateKey: string; calories: number }>;
    weights: Array<{ recordedAt: Date; valueKg: number }>;
  },
): TrendBucket[] {
  const byStart = new Map<number, TrendBucket>();
  for (const start of plan.starts) {
    byStart.set(start.getTime(), {
      ts: start.toISOString(),
      workouts: 0,
      workoutMinutes: 0,
      runs: 0,
      runMeters: 0,
      calories: 0,
      weightKg: null,
    });
  }

  for (const w of rows.workouts) {
    const bucket = resolveBucketStart(w.startedAt, plan);
    if (!bucket) continue;
    const entry = byStart.get(bucket.getTime());
    if (!entry) continue;
    entry.workouts += 1;
    entry.workoutMinutes += Math.max(0, w.durationMinutes || 0);
  }

  for (const r of rows.runs) {
    const bucket = resolveBucketStart(r.startedAt, plan);
    if (!bucket) continue;
    const entry = byStart.get(bucket.getTime());
    if (!entry) continue;
    entry.runs += 1;
    entry.runMeters += Math.max(0, r.distanceMeters || 0);
  }

  for (const meal of rows.meals) {
    const bucket = resolveBucketStartFromDateKey(meal.dateKey, plan);
    if (!bucket) continue;
    const entry = byStart.get(bucket.getTime());
    if (!entry) continue;
    entry.calories += Math.max(0, meal.calories || 0);
  }

  // Weights: pick the *latest* reading that falls inside each bucket.
  // Incoming rows are assumed pre-sorted ascending by recordedAt so the last
  // write wins (matches the response contract — "latest weight reading in
  // bucket"). Defensive sort in case the caller passes them unsorted.
  const sortedWeights = [...rows.weights].sort(
    (a, b) => a.recordedAt.getTime() - b.recordedAt.getTime(),
  );
  for (const weight of sortedWeights) {
    const bucket = resolveBucketStart(weight.recordedAt, plan);
    if (!bucket) continue;
    const entry = byStart.get(bucket.getTime());
    if (!entry) continue;
    entry.weightKg = Math.round(weight.valueKg * 10) / 10;
  }

  return plan.starts.map((s) => byStart.get(s.getTime())!);
}

/** kg/lb normalization for weight HealthMetrics. */
export function normalizeWeightKg(value: number, unit: string): number {
  if (unit === 'lb') {
    return value * 0.45359237;
  }
  return value;
}

/**
 * Derive the response-level summary. Separate from composeBuckets so tests
 * can target it independently.
 */
export function buildSummary(
  range: TrendRange,
  buckets: TrendBucket[],
): TrendResponse['summary'] {
  const totalWorkouts = buckets.reduce((t, b) => t + b.workouts, 0);
  const totalRuns = buckets.reduce((t, b) => t + b.runs, 0);
  const totalCalories = buckets.reduce((t, b) => t + b.calories, 0);

  let avgWorkoutsPerWeek = 0;
  if (range === 'month') {
    // 30 daily buckets ≈ 30/7 weeks.
    avgWorkoutsPerWeek = totalWorkouts > 0
      ? Math.round(((totalWorkouts / 30) * 7) * 10) / 10
      : 0;
  } else if (range === 'year') {
    // 12 monthly buckets ≈ 52 weeks.
    avgWorkoutsPerWeek = totalWorkouts > 0
      ? Math.round((totalWorkouts / 52) * 10) / 10
      : 0;
  }

  return {
    totalWorkouts,
    totalRuns,
    totalCalories: Math.round(totalCalories),
    avgWorkoutsPerWeek,
  };
}

const router = Router();

// GET /api/v1/metrics/trends?range=week|month|year&timezone=America/Los_Angeles
router.get('/trends', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const rawRange = req.query.range;
    if (!isSupportedRange(rawRange)) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'range must be one of: week, month, year',
      );
      return;
    }
    const range: TrendRange = rawRange;
    const timezone = sanitizeTimezone(req.query.timezone);
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);

    const now = new Date();
    const plan = buildBucketPlan(range, now);
    const firstStart = plan.starts[0]!;
    const lastStart = plan.starts[plan.starts.length - 1]!;
    const windowEnd = new Date(lastStart);
    if (plan.granularity === 'day') {
      windowEnd.setUTCDate(windowEnd.getUTCDate() + 1);
    } else {
      windowEnd.setUTCMonth(windowEnd.getUTCMonth() + 1);
    }

    const firstDateKey = firstStart.toISOString().slice(0, 10);
    const lastDateKey = new Date(windowEnd.getTime() - 1).toISOString().slice(0, 10);

    const [workoutDocs, runDocs, mealDocs, weightDocs] = await Promise.all([
      Workout.find({
        userId,
        endedAt: { $ne: null },
        startedAt: { $gte: firstStart, $lt: windowEnd },
      })
        .select('startedAt durationMinutes')
        .lean(),
      Run.find({
        userId,
        endedAt: { $ne: null },
        startedAt: { $gte: firstStart, $lt: windowEnd },
      })
        .select('startedAt distanceMeters')
        .lean(),
      Meal.find({
        userId,
        date: { $gte: firstDateKey, $lte: lastDateKey },
      })
        .select('date calories')
        .lean(),
      HealthMetric.find({
        userId,
        metricType: 'weight',
        recordedAt: { $gte: firstStart, $lt: windowEnd },
      })
        .sort({ recordedAt: 1 })
        .select('recordedAt value unit')
        .lean(),
    ]);

    const buckets = composeBuckets(plan, {
      workouts: workoutDocs.map((w) => ({
        startedAt: w.startedAt,
        durationMinutes: w.durationMinutes ?? 0,
      })),
      runs: runDocs.map((r) => ({
        startedAt: r.startedAt,
        distanceMeters: r.distanceMeters ?? 0,
      })),
      meals: mealDocs.map((m) => ({
        dateKey: m.date,
        calories: m.calories ?? 0,
      })),
      weights: weightDocs.map((w) => ({
        recordedAt: w.recordedAt,
        valueKg: normalizeWeightKg(w.value, w.unit),
      })),
    });

    const payload: TrendResponse = {
      range,
      timezone,
      buckets,
      summary: buildSummary(range, buckets),
    };

    successResponse(res, payload);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load metrics trends',
      (err as Error).message,
    );
  }
});

export default router;
