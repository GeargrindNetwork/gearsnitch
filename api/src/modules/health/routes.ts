import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { HealthMetric } from '../../models/HealthMetric.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

type CanonicalMetricType =
  | 'weight'
  | 'height'
  | 'bmi'
  | 'active_calories'
  | 'steps'
  | 'resting_heart_rate'
  | 'workout_session';

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
    case 'heart_rate':
    case 'heartrate':
      return 'resting_heart_rate';
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
      return { value, unit: 'bpm' };
    default:
      break;
  }

  throw new HealthValidationError(`Unsupported unit "${unit}" for metric type "${metricType}"`);
}

function normalizeMetricSource(source: string): 'manual' | 'apple_health' {
  return normalizeToken(source) === 'manual' ? 'manual' : 'apple_health';
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

router.get('/', isAuthenticated, handleMetricsSnapshot);
router.post('/sync', isAuthenticated, validateBody(healthSyncBodySchema), handleHealthSync);
router.post('/apple/sync', isAuthenticated, validateBody(healthSyncBodySchema), handleHealthSync);
router.get('/metrics', isAuthenticated, handleMetricsSnapshot);
router.get('/history', isAuthenticated, handleHealthHistory);

export default router;
