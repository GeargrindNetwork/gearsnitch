import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { HealthMetric } from '../../models/HealthMetric.js';
import { Device } from '../../models/Device.js';
import { GymSession } from '../../models/GymSession.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

type CanonicalMetricType =
  | 'weight'
  | 'height'
  | 'bmi'
  | 'active_calories'
  | 'steps'
  | 'resting_heart_rate'
  | 'workout_session'
  | 'heart_rate';

type CanonicalUnit = 'kg' | 'lb' | 'cm' | 'in' | 'bmi' | 'kcal' | 'steps' | 'bpm';

const healthMetricSyncSchema = z.object({
  type: z.string().trim().min(1).max(64),
  value: z.number().finite(),
  unit: z.string().trim().min(1).max(32),
  startDate: z.string().datetime(),
  endDate: z.string().datetime(),
  source: z.string().trim().min(1).max(120).optional().default('apple_health'),
}).superRefine((value, ctx) => {
  if (new Date(value.endDate) < new Date(value.startDate)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['endDate'],
      message: 'endDate must be greater than or equal to startDate',
    });
  }
});

const healthSyncBodySchema = z.object({
  metrics: z.array(healthMetricSyncSchema).min(1).max(500),
});

type HealthMetricSyncInput = z.infer<typeof healthMetricSyncSchema>;

class HealthValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'HealthValidationError';
  }
}

function normalizeToken(value: string): string {
  return value
    .trim()
    .replace(/([a-z])([A-Z])/g, '$1_$2')
    .replace(/[\s-]+/g, '_')
    .toLowerCase();
}

function parseMetricTypes(value: unknown): CanonicalMetricType[] {
  if (typeof value !== 'string' || !value.trim()) {
    return [];
  }

  return value
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => normalizeMetricType(entry));
}

function normalizeMetricType(value: string): CanonicalMetricType {
  const token = normalizeToken(value);

  switch (token) {
    case 'weight':
      return 'weight';
    case 'height':
      return 'height';
    case 'bmi':
      return 'bmi';
    case 'active_calories':
    case 'calories':
      return 'active_calories';
    case 'steps':
    case 'step_count':
    case 'count':
      return 'steps';
    case 'resting_heart_rate':
      return 'resting_heart_rate';
    case 'heart_rate':
    case 'heartrate':
    case 'instantaneous_heart_rate':
      return 'heart_rate';
    case 'workout':
    case 'workout_session':
      return 'workout_session';
    default:
      throw new HealthValidationError(`Unsupported health metric type: ${value}`);
  }
}

function normalizeMetricUnit(
  metricType: CanonicalMetricType,
  value: number,
  unit: string,
): { value: number; unit: CanonicalUnit } {
  const token = normalizeToken(unit);

  switch (metricType) {
    case 'weight':
      if (['kg', 'kilogram', 'kilograms'].includes(token)) {
        return { value, unit: 'kg' };
      }
      if (['lb', 'lbs', 'pound', 'pounds'].includes(token)) {
        return { value, unit: 'lb' };
      }
      break;
    case 'height':
      if (['cm', 'centimeter', 'centimeters'].includes(token)) {
        return { value, unit: 'cm' };
      }
      if (['m', 'meter', 'meters'].includes(token)) {
        return { value: Math.round(value * 1000) / 10, unit: 'cm' };
      }
      if (['in', 'inch', 'inches'].includes(token)) {
        return { value, unit: 'in' };
      }
      break;
    case 'bmi':
      return { value, unit: 'bmi' };
    case 'active_calories':
    case 'workout_session':
      return { value, unit: 'kcal' };
    case 'steps':
      return { value, unit: 'steps' };
    case 'resting_heart_rate':
    case 'heart_rate':
      return { value, unit: 'bpm' };
    default:
      break;
  }

  throw new HealthValidationError(`Unsupported unit "${unit}" for metric type "${metricType}"`);
}

function normalizeMetricSource(source: string): 'manual' | 'apple_health' | 'airpods_pro' {
  const token = normalizeToken(source);
  if (token === 'manual') return 'manual';
  if (token === 'airpods_pro' || token === 'airpods') return 'airpods_pro';
  return 'apple_health';
}

function serializeHealthMetric(metric: Record<string, any>) {
  return {
    _id: String(metric._id),
    userId: String(metric.userId),
    metricType: metric.metricType,
    value: metric.value,
    unit: metric.unit,
    source: metric.source,
    recordedAt: metric.recordedAt,
    createdAt: metric.createdAt,
  };
}

function parseOptionalQueryDate(value: unknown, label: string): Date | null {
  if (typeof value !== 'string' || !value.trim()) {
    return null;
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new HealthValidationError(`Invalid ${label} date: ${value}`);
  }

  return parsed;
}

function buildHistoryFilter(userId: string, req: Request) {
  const filter: Record<string, unknown> = {
    userId: new Types.ObjectId(userId),
  };

  const metricTypes = parseMetricTypes(req.query.type ?? req.query.metricType ?? req.query.types);
  if (metricTypes.length === 1) {
    filter.metricType = metricTypes[0];
  } else if (metricTypes.length > 1) {
    filter.metricType = { $in: metricTypes };
  }

  const from = parseOptionalQueryDate(req.query.from, 'from');
  const to = parseOptionalQueryDate(req.query.to, 'to');

  if (from || to) {
    filter.recordedAt = {
      ...(from ? { $gte: from } : {}),
      ...(to ? { $lte: to } : {}),
    };
  }

  return filter;
}

function normalizeSyncedMetric(metric: HealthMetricSyncInput, userId: string) {
  const metricType = normalizeMetricType(metric.type);
  const normalizedValue = normalizeMetricUnit(metricType, metric.value, metric.unit);

  return {
    userId: new Types.ObjectId(userId),
    metricType,
    value: normalizedValue.value,
    unit: normalizedValue.unit,
    source: normalizeMetricSource(metric.source ?? 'apple_health'),
    recordedAt: new Date(metric.endDate),
  };
}

async function handleHealthSync(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const { metrics } = req.body as z.infer<typeof healthSyncBodySchema>;
    const normalizedMetrics = metrics.map((metric) => normalizeSyncedMetric(metric, user.sub));

    const result = await HealthMetric.bulkWrite(
      normalizedMetrics.map((metric) => ({
        updateOne: {
          filter: {
            userId: metric.userId,
            metricType: metric.metricType,
            value: metric.value,
            unit: metric.unit,
            source: metric.source,
            recordedAt: metric.recordedAt,
          },
          update: { $setOnInsert: metric },
          upsert: true,
        },
      })),
      { ordered: false },
    );

    successResponse(
      res,
      {
        received: metrics.length,
        inserted: result.upsertedCount,
        deduplicated: result.matchedCount,
      },
      StatusCodes.CREATED,
    );
  } catch (err) {
    if (err instanceof HealthValidationError) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Failed to sync health data', err.message);
      return;
    }

    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to sync health data',
      (err as Error).message,
    );
  }
}

async function handleMetricsSnapshot(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const filter = buildHistoryFilter(user.sub, req);

    const metrics = await HealthMetric.aggregate([
      { $match: filter },
      { $sort: { recordedAt: -1, createdAt: -1 } },
      { $group: { _id: '$metricType', metric: { $first: '$$ROOT' } } },
      { $replaceRoot: { newRoot: '$metric' } },
      { $sort: { metricType: 1 } },
    ]);

    successResponse(res, metrics.map(serializeHealthMetric));
  } catch (err) {
    if (err instanceof HealthValidationError) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Failed to load health metrics', err.message);
      return;
    }

    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load health metrics',
      (err as Error).message,
    );
  }
}

async function handleHealthHistory(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(250, Math.max(1, parseInt(req.query.limit as string, 10) || 50));
    const skip = (page - 1) * limit;
    const filter = buildHistoryFilter(user.sub, req);

    const [metrics, total] = await Promise.all([
      HealthMetric.find(filter)
        .sort({ recordedAt: -1, createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      HealthMetric.countDocuments(filter),
    ]);

    successResponse(
      res,
      metrics.map(serializeHealthMetric),
      StatusCodes.OK,
      {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    );
  } catch (err) {
    if (err instanceof HealthValidationError) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Failed to load health history', err.message);
      return;
    }

    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load health history',
      (err as Error).message,
    );
  }
}

// ─── Heart Rate Batch & Summary ───────────────────────────────────────────

const heartRateSampleSchema = z.object({
  bpm: z.number().int().min(30).max(250),
  recordedAt: z.string().datetime(),
  source: z.string().max(120).optional().default('airpods_pro'),
});

const heartRateBatchBodySchema = z.object({
  samples: z.array(heartRateSampleSchema).min(1).max(500),
  sessionId: z.string().optional(),
});

function classifyHeartRateZone(bpm: number): string {
  if (bpm < 100) return 'rest';
  if (bpm < 120) return 'light';
  if (bpm < 140) return 'fatBurn';
  if (bpm < 160) return 'cardio';
  return 'peak';
}

async function handleHeartRateBatch(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const { samples, sessionId: _sessionId } = req.body as z.infer<typeof heartRateBatchBodySchema>;

    const docs = samples.map((sample) => ({
      userId: new Types.ObjectId(user.sub),
      metricType: 'heart_rate' as const,
      value: sample.bpm,
      unit: 'bpm' as const,
      source: normalizeMetricSource(sample.source ?? 'airpods_pro'),
      recordedAt: new Date(sample.recordedAt),
    }));

    const result = await HealthMetric.bulkWrite(
      docs.map((doc) => ({
        updateOne: {
          filter: {
            userId: doc.userId,
            metricType: doc.metricType,
            recordedAt: doc.recordedAt,
          },
          update: { $setOnInsert: doc },
          upsert: true,
        },
      })),
      { ordered: false },
    );

    successResponse(
      res,
      {
        received: samples.length,
        inserted: result.upsertedCount,
        deduplicated: result.matchedCount,
      },
      StatusCodes.CREATED,
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to ingest heart rate samples',
      (err as Error).message,
    );
  }
}

async function handleHeartRateSessionSummary(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const from = parseOptionalQueryDate(req.query.from, 'from');
    const to = parseOptionalQueryDate(req.query.to, 'to');

    if (!from || !to) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Missing required query params', 'Both "from" and "to" are required');
      return;
    }

    const samples = await HealthMetric.find({
      userId: new Types.ObjectId(user.sub),
      metricType: 'heart_rate',
      recordedAt: { $gte: from, $lte: to },
    })
      .sort({ recordedAt: 1 })
      .lean();

    if (samples.length === 0) {
      successResponse(res, {
        sessionId: (req.query.sessionId as string) || null,
        from: from.toISOString(),
        to: to.toISOString(),
        sampleCount: 0,
        minBPM: 0,
        maxBPM: 0,
        avgBPM: 0,
        zoneDistribution: { rest: 0, light: 0, fatBurn: 0, cardio: 0, peak: 0 },
      });
      return;
    }

    let min = Infinity;
    let max = -Infinity;
    let sum = 0;
    const zoneCounts: Record<string, number> = {
      rest: 0,
      light: 0,
      fatBurn: 0,
      cardio: 0,
      peak: 0,
    };

    for (const sample of samples) {
      const bpm = sample.value;
      if (bpm < min) min = bpm;
      if (bpm > max) max = bpm;
      sum += bpm;
      zoneCounts[classifyHeartRateZone(bpm)]++;
    }

    const count = samples.length;
    const zoneDistribution = {
      rest: Math.round((zoneCounts.rest / count) * 1000) / 10,
      light: Math.round((zoneCounts.light / count) * 1000) / 10,
      fatBurn: Math.round((zoneCounts.fatBurn / count) * 1000) / 10,
      cardio: Math.round((zoneCounts.cardio / count) * 1000) / 10,
      peak: Math.round((zoneCounts.peak / count) * 1000) / 10,
    };

    successResponse(res, {
      sessionId: (req.query.sessionId as string) || null,
      from: from.toISOString(),
      to: to.toISOString(),
      sampleCount: count,
      minBPM: min,
      maxBPM: max,
      avgBPM: Math.round((sum / count) * 10) / 10,
      zoneDistribution,
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to compute heart rate summary',
      (err as Error).message,
    );
  }
}

// ─── Health Dashboard ─────────────────────────────────────────────────────────

async function handleHealthDashboard(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);

    const [latestHR, todayHRSamples, todaySessions, activeSession, devices, sourceCounts] =
      await Promise.all([
        // Latest heart rate sample
        HealthMetric.findOne({
          userId,
          metricType: 'heart_rate',
        })
          .sort({ recordedAt: -1 })
          .lean(),

        // Today's HR samples for aggregate stats
        HealthMetric.find({
          userId,
          metricType: 'heart_rate',
          recordedAt: { $gte: startOfDay },
        })
          .sort({ recordedAt: 1 })
          .lean(),

        // Today's gym sessions
        GymSession.find({
          userId,
          startedAt: { $gte: startOfDay },
        })
          .sort({ startedAt: -1 })
          .lean(),

        // Active session (no endedAt)
        GymSession.findOne({
          userId,
          endedAt: null,
        }).lean(),

        // User's devices
        Device.find({ userId })
          .sort({ isFavorite: -1, updatedAt: -1 })
          .lean(),

        // Source attribution: distinct sources with counts today
        HealthMetric.aggregate([
          {
            $match: {
              userId,
              metricType: 'heart_rate',
              recordedAt: { $gte: startOfDay },
            },
          },
          {
            $group: {
              _id: '$source',
              count: { $sum: 1 },
              lastDataAt: { $max: '$recordedAt' },
            },
          },
        ]),
      ]);

    // Compute today's HR aggregate
    let todayHR = null;
    if (todayHRSamples.length > 0) {
      let min = Infinity;
      let max = -Infinity;
      let sum = 0;
      const zoneCounts: Record<string, number> = {
        rest: 0, light: 0, fatBurn: 0, cardio: 0, peak: 0,
      };

      for (const s of todayHRSamples) {
        const bpm = s.value;
        if (bpm < min) min = bpm;
        if (bpm > max) max = bpm;
        sum += bpm;
        zoneCounts[classifyHeartRateZone(bpm)]++;
      }

      const count = todayHRSamples.length;
      todayHR = {
        sampleCount: count,
        minBPM: min,
        maxBPM: max,
        avgBPM: Math.round((sum / count) * 10) / 10,
        zoneDistribution: {
          rest: Math.round((zoneCounts.rest / count) * 1000) / 10,
          light: Math.round((zoneCounts.light / count) * 1000) / 10,
          fatBurn: Math.round((zoneCounts.fatBurn / count) * 1000) / 10,
          cardio: Math.round((zoneCounts.cardio / count) * 1000) / 10,
          peak: Math.round((zoneCounts.peak / count) * 1000) / 10,
        },
      };
    }

    // Map source names
    const sourceNameMap: Record<string, { name: string; type: string }> = {
      airpods_pro: { name: 'AirPods Pro 3', type: 'airpods_pro' },
      apple_health: { name: 'Apple Health', type: 'apple_health' },
      apple_watch: { name: 'Apple Watch', type: 'apple_watch' },
      manual: { name: 'Manual', type: 'manual' },
    };

    const healthCapableTypes = new Set(['earbuds', 'watch']);

    successResponse(res, {
      heartRate: {
        latest: latestHR
          ? {
              bpm: latestHR.value,
              recordedAt: latestHR.recordedAt.toISOString(),
              source: latestHR.source,
            }
          : null,
        today: todayHR,
      },
      sessions: {
        today: todaySessions.map((s) => ({
          _id: String(s._id),
          gymName: s.gymName || 'Unknown Gym',
          startedAt: s.startedAt.toISOString(),
          endedAt: s.endedAt ? s.endedAt.toISOString() : null,
          durationMinutes: s.durationMinutes || null,
          heartRateSummary: null, // Computed on demand via session-summary endpoint
        })),
        activeSession: activeSession
          ? {
              _id: String(activeSession._id),
              gymName: activeSession.gymName || 'Unknown Gym',
              startedAt: activeSession.startedAt.toISOString(),
            }
          : null,
      },
      devices: devices.map((d) => ({
        _id: String(d._id),
        name: d.name,
        nickname: d.nickname || null,
        type: d.type,
        status: d.status,
        isFavorite: d.isFavorite,
        lastSeenAt: d.lastSeenAt ? d.lastSeenAt.toISOString() : null,
        healthCapable: healthCapableTypes.has(d.type),
      })),
      sources: sourceCounts.map((s: { _id: string; count: number; lastDataAt: Date }) => ({
        name: sourceNameMap[s._id]?.name || s._id,
        type: sourceNameMap[s._id]?.type || s._id,
        lastDataAt: s.lastDataAt ? s.lastDataAt.toISOString() : null,
        sampleCountToday: s.count,
      })),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load health dashboard',
      (err as Error).message,
    );
  }
}

// ─── Routes ──────────────────────────────────────────────────────────────────

// ─── Health Trends ────────────────────────────────────────────────────────────

async function handleHealthTrends(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);
    const days = Math.min(365, Math.max(1, parseInt(req.query.days as string, 10) || 30));
    const since = new Date();
    since.setDate(since.getDate() - days);

    const [hrSamples, restingHR, weightSamples, caloriesByDay, workoutSessions] = await Promise.all([
      // HR scatter — all instantaneous heart rate samples
      HealthMetric.find({
        userId,
        metricType: 'heart_rate',
        recordedAt: { $gte: since },
      })
        .sort({ recordedAt: 1 })
        .limit(2000)
        .lean(),

      // Resting heart rate trend
      HealthMetric.find({
        userId,
        metricType: 'resting_heart_rate',
        recordedAt: { $gte: since },
      })
        .sort({ recordedAt: 1 })
        .lean(),

      // Weight trend
      HealthMetric.find({
        userId,
        metricType: 'weight',
        recordedAt: { $gte: since },
      })
        .sort({ recordedAt: 1 })
        .lean(),

      // Active calories grouped by day
      HealthMetric.aggregate([
        {
          $match: {
            userId,
            metricType: 'active_calories',
            recordedAt: { $gte: since },
          },
        },
        {
          $group: {
            _id: {
              $dateToString: { format: '%Y-%m-%d', date: '$recordedAt' },
            },
            totalKcal: { $sum: '$value' },
            date: { $first: '$recordedAt' },
          },
        },
        { $sort: { _id: 1 } },
      ]),

      // Workout sessions
      GymSession.find({
        userId,
        startedAt: { $gte: since },
      })
        .sort({ startedAt: 1 })
        .lean(),
    ]);

    // Format HR scatter
    const hrScatter = hrSamples.map((s) => ({
      date: s.recordedAt.toISOString(),
      bpm: s.value,
      zone: classifyHeartRateZone(s.value),
    }));

    // Format resting HR
    const restingHRTrend = restingHR.map((s) => ({
      date: s.recordedAt.toISOString(),
      value: s.value,
    }));

    // Format weight
    const weightTrend = weightSamples.map((s) => ({
      date: s.recordedAt.toISOString(),
      value: s.value,
      unit: s.unit,
    }));

    // Format calories
    const caloriesTrend = caloriesByDay.map((d: { _id: string; totalKcal: number; date: Date }) => ({
      date: d.date.toISOString(),
      value: d.totalKcal,
    }));

    // Group workouts by day
    const workoutsByDay = new Map<string, { count: number; durationMinutes: number; date: Date }>();
    for (const session of workoutSessions) {
      const dateKey = session.startedAt.toISOString().substring(0, 10);
      const existing = workoutsByDay.get(dateKey) || { count: 0, durationMinutes: 0, date: session.startedAt };
      existing.count += 1;
      existing.durationMinutes += session.durationMinutes || 0;
      workoutsByDay.set(dateKey, existing);
    }

    const workoutTrend = Array.from(workoutsByDay.entries())
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([, data]) => ({
        date: data.date.toISOString(),
        count: data.count,
        durationMinutes: data.durationMinutes,
      }));

    successResponse(res, {
      days,
      since: since.toISOString(),
      heartRateScatter: hrScatter,
      restingHeartRate: restingHRTrend,
      weightTrend,
      caloriesTrend,
      workoutTrend,
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load health trends',
      (err as Error).message,
    );
  }
}

router.get('/trends', isAuthenticated, handleHealthTrends);
router.get('/dashboard', isAuthenticated, handleHealthDashboard);
router.get('/', isAuthenticated, handleMetricsSnapshot);
router.post('/sync', isAuthenticated, validateBody(healthSyncBodySchema), handleHealthSync);
router.post('/apple/sync', isAuthenticated, validateBody(healthSyncBodySchema), handleHealthSync);
router.get('/metrics', isAuthenticated, handleMetricsSnapshot);
router.get('/history', isAuthenticated, handleHealthHistory);
router.post('/heart-rate/batch', isAuthenticated, validateBody(heartRateBatchBodySchema), handleHeartRateBatch);
router.get('/heart-rate/session-summary', isAuthenticated, handleHeartRateSessionSummary);

export default router;
