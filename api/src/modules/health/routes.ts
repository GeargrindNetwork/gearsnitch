import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { HealthMetric } from '../../models/HealthMetric.js';
import { errorResponse, successResponse } from '../../utils/response.js';

const router = Router();

const syncMetricSchema = z.object({
  type: z.string().trim().min(1),
  value: z.coerce.number().finite(),
  unit: z.string().trim().min(1),
  startDate: z.coerce.date(),
  endDate: z.coerce.date(),
  source: z.string().trim().min(1).optional().default('apple_health'),
});

const syncBodySchema = z.object({
  metrics: z.array(syncMetricSchema).max(1000),
});

type SyncMetricBody = z.infer<typeof syncMetricSchema>;

type NormalizedMetricType =
  | 'weight'
  | 'height'
  | 'bmi'
  | 'active_calories'
  | 'steps'
  | 'resting_heart_rate'
  | 'workout_session';

type NormalizedUnit = 'kg' | 'lb' | 'cm' | 'in' | 'bmi' | 'kcal' | 'steps' | 'bpm';
type NormalizedSource = 'manual' | 'apple_health';

interface NormalizedMetric {
  metricType: NormalizedMetricType;
  value: number;
  unit: NormalizedUnit;
  source: NormalizedSource;
  recordedAt: Date;
}

function getUserId(req: Request): Types.ObjectId {
  return new Types.ObjectId((req.user as JwtPayload).sub);
}

function normalizeMetricType(type: string): NormalizedMetricType | null {
  switch (type) {
    case 'weight':
      return 'weight';
    case 'height':
      return 'height';
    case 'bmi':
      return 'bmi';
    case 'active_calories':
      return 'active_calories';
    case 'steps':
      return 'steps';
    case 'resting_heart_rate':
      return 'resting_heart_rate';
    case 'workout':
    case 'workout_session':
      return 'workout_session';
    default:
      return null;
  }
}

function normalizeUnit(metricType: NormalizedMetricType, unit: string): NormalizedUnit | null {
  switch (metricType) {
    case 'weight':
      return unit === 'lb' ? 'lb' : unit === 'kg' ? 'kg' : null;
    case 'height':
      return unit === 'in' ? 'in' : unit === 'cm' ? 'cm' : null;
    case 'bmi':
      return unit === 'count' || unit === 'bmi' ? 'bmi' : null;
    case 'active_calories':
    case 'workout_session':
      return unit === 'kcal' || unit === 'Cal' ? 'kcal' : null;
    case 'steps':
      return unit === 'count' || unit === 'steps' ? 'steps' : null;
    case 'resting_heart_rate':
      return unit === 'count/min' || unit === 'bpm' ? 'bpm' : null;
    default:
      return null;
  }
}

function normalizeMetric(metric: SyncMetricBody): NormalizedMetric | null {
  const metricType = normalizeMetricType(metric.type);
  if (!metricType) {
    return null;
  }

  const unit = normalizeUnit(metricType, metric.unit);
  if (!unit) {
    return null;
  }

  return {
    metricType,
    value: metric.value,
    unit,
    source: metric.source === 'manual' ? ('manual' as const) : ('apple_health' as const),
    recordedAt: metric.endDate,
  };
}

async function handleSync(req: Request, res: Response) {
  try {
    const body = req.body as z.infer<typeof syncBodySchema>;
    const userId = getUserId(req);
    const normalizedMetrics = body.metrics
      .map((metric) => normalizeMetric(metric))
      .filter((metric): metric is NonNullable<typeof metric> => metric !== null);

    if (normalizedMetrics.length === 0) {
      successResponse(res, { inserted: 0, skipped: body.metrics.length });
      return;
    }

    await HealthMetric.insertMany(
      normalizedMetrics.map((metric) => ({
        userId,
        metricType: metric.metricType,
        value: metric.value,
        unit: metric.unit,
        source: metric.source,
        recordedAt: metric.recordedAt,
      })),
      { ordered: false }
    );

    successResponse(res, {
      inserted: normalizedMetrics.length,
      skipped: body.metrics.length - normalizedMetrics.length,
      matched: 0,
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to sync health metrics',
      err instanceof Error ? err.message : String(err),
    );
  }
}

// GET /health-data
router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const metrics = await HealthMetric.find({ userId: getUserId(req) })
      .sort({ recordedAt: -1 })
      .limit(50)
      .lean();

    successResponse(res, metrics);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load health data',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /health-data/sync and /health-data/apple/sync
router.post('/sync', isAuthenticated, validateBody(syncBodySchema), handleSync);
router.post('/apple/sync', isAuthenticated, validateBody(syncBodySchema), handleSync);

// GET /health-data/metrics
router.get('/metrics', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const metrics = await HealthMetric.find({ userId: getUserId(req) })
      .sort({ recordedAt: -1 })
      .limit(200)
      .lean();

    const latestByType = Array.from(
      metrics.reduce((map, metric) => {
        if (!map.has(metric.metricType)) {
          map.set(metric.metricType, metric);
        }
        return map;
      }, new Map<string, Record<string, any>>()).values(),
    );

    successResponse(res, latestByType);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load health metrics',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /health-data/history
router.get('/history', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const history = await HealthMetric.find({ userId: getUserId(req) })
      .sort({ recordedAt: -1 })
      .limit(500)
      .lean();

    successResponse(res, history);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load health history',
      err instanceof Error ? err.message : String(err),
    );
  }
});

export default router;
