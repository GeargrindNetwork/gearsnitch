import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { Run, type IRunPoint } from '../../models/Run.js';
import {
  resolveDefaultGear,
  logAutoGearAssigned,
  incrementGearForWorkoutMetrics,
} from '../gear/autoAttach.js';
import { User } from '../../models/User.js';
import { enqueuePushNotification } from '../../services/pushNotificationQueue.js';
import logger from '../../utils/logger.js';
import { successResponse, errorResponse } from '../../utils/response.js';

/**
 * Item #27 — run-completion summary push. Mirrors the workout flow but with
 * run-specific copy (distance, pace, optional avg HR if it's ever wired in).
 *
 * Floor below which we skip the push entirely. Apple Fitness ignores anything
 * shorter than ~1 minute / a few hundred metres; we use the same idea so the
 * user isn't pinged for a 5-second accidental Start→Stop.
 */
const RUN_SUMMARY_PUSH_MIN_DURATION_SECONDS = 60;
const RUN_SUMMARY_PUSH_MIN_DISTANCE_METERS = 50;

const router = Router();
const EARTH_RADIUS_METERS = 6_371_000;

const runPointSchema = z.object({
  latitude: z.number().finite().min(-90).max(90),
  longitude: z.number().finite().min(-180).max(180),
  timestamp: z.string().datetime(),
  altitudeMeters: z.number().finite().nullable().optional(),
  horizontalAccuracyMeters: z.number().finite().min(0).nullable().optional(),
  speedMetersPerSecond: z.number().finite().nullable().optional(),
});

const OBJECT_ID_REGEX = /^[a-fA-F0-9]{24}$/;

const startRunSchema = z.object({
  startedAt: z.string().datetime().optional(),
  source: z.enum(['ios', 'manual']).optional().default('ios'),
  notes: z.string().trim().max(2_000).optional(),
  routePoints: z.array(runPointSchema).optional().default([]),
  gearId: z.union([z.string().regex(OBJECT_ID_REGEX), z.null()]).optional(),
  gearIds: z.array(z.string().regex(OBJECT_ID_REGEX)).max(8).optional(),
});

const completeRunSchema = z.object({
  endedAt: z.string().datetime().optional(),
  distanceMeters: z.number().finite().min(0).optional(),
  notes: z.union([z.string().trim().max(2_000), z.null()]).optional(),
  routePoints: z.array(runPointSchema).optional(),
});

type RunPointInput = z.infer<typeof runPointSchema>;
type StartRunBody = z.infer<typeof startRunSchema>;
type CompleteRunBody = z.infer<typeof completeRunSchema>;

function toRadians(value: number): number {
  return (value * Math.PI) / 180;
}

function roundToSingleDecimal(value: number): number {
  return Math.round(value * 10) / 10;
}

function normalizeRoutePoints(points: RunPointInput[] | IRunPoint[] | undefined): IRunPoint[] {
  return Array.isArray(points)
    ? points.map((point) => ({
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: point.timestamp instanceof Date ? point.timestamp : new Date(point.timestamp),
        altitudeMeters: point.altitudeMeters ?? null,
        horizontalAccuracyMeters: point.horizontalAccuracyMeters ?? null,
        speedMetersPerSecond: point.speedMetersPerSecond ?? null,
      }))
    : [];
}

function computeDistanceMeters(points: IRunPoint[]): number {
  if (points.length < 2) {
    return 0;
  }

  let total = 0;

  for (let index = 1; index < points.length; index += 1) {
    const previous = points[index - 1];
    const current = points[index];

    const latitudeDelta = toRadians(current.latitude - previous.latitude);
    const longitudeDelta = toRadians(current.longitude - previous.longitude);
    const latitudeA = toRadians(previous.latitude);
    const latitudeB = toRadians(current.latitude);

    const haversine =
      (Math.sin(latitudeDelta / 2) ** 2)
      + Math.cos(latitudeA) * Math.cos(latitudeB) * (Math.sin(longitudeDelta / 2) ** 2);
    const arc = 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
    total += EARTH_RADIUS_METERS * arc;
  }

  return roundToSingleDecimal(total);
}

function computeDurationSeconds(startedAt: Date, endedAt: Date | null): number {
  if (!endedAt) {
    return 0;
  }

  return Math.max(0, Math.round((endedAt.getTime() - startedAt.getTime()) / 1_000));
}

function computeAveragePaceSecondsPerKm(distanceMeters: number, durationSeconds: number): number | null {
  if (distanceMeters <= 0 || durationSeconds <= 0) {
    return null;
  }

  return Math.round(durationSeconds / (distanceMeters / 1_000));
}

function computeBounds(points: IRunPoint[]) {
  if (points.length === 0) {
    return null;
  }

  let minLatitude = points[0].latitude;
  let maxLatitude = points[0].latitude;
  let minLongitude = points[0].longitude;
  let maxLongitude = points[0].longitude;

  for (const point of points) {
    minLatitude = Math.min(minLatitude, point.latitude);
    maxLatitude = Math.max(maxLatitude, point.latitude);
    minLongitude = Math.min(minLongitude, point.longitude);
    maxLongitude = Math.max(maxLongitude, point.longitude);
  }

  return {
    minLatitude,
    maxLatitude,
    minLongitude,
    maxLongitude,
  };
}

function serializeRunSummary(run: Record<string, any>) {
  const startedAt = run.startedAt instanceof Date ? run.startedAt : new Date(run.startedAt);
  const endedAt =
    run.endedAt instanceof Date || run.endedAt === null
      ? run.endedAt
      : new Date(run.endedAt);
  const routePoints = normalizeRoutePoints(run.routePoints);
  const distanceMeters = typeof run.distanceMeters === 'number'
    ? roundToSingleDecimal(run.distanceMeters)
    : computeDistanceMeters(routePoints);
  const durationSeconds = typeof run.durationSeconds === 'number'
    ? run.durationSeconds
    : computeDurationSeconds(startedAt, endedAt);
  const averagePaceSecondsPerKm = typeof run.averagePaceSecondsPerKm === 'number'
    ? run.averagePaceSecondsPerKm
    : computeAveragePaceSecondsPerKm(distanceMeters, durationSeconds);

  return {
    _id: String(run._id),
    startedAt,
    endedAt,
    status: endedAt ? 'completed' : 'active',
    durationSeconds,
    durationMinutes: roundToSingleDecimal(durationSeconds / 60),
    distanceMeters,
    averagePaceSecondsPerKm,
    source: run.source,
    notes: run.notes ?? null,
    gearId: run.gearId ? String(run.gearId) : null,
    gearIds: Array.isArray(run.gearIds)
      ? run.gearIds.map((id: unknown) => String(id))
      : [],
    route: {
      pointCount: routePoints.length,
      bounds: computeBounds(routePoints),
    },
    createdAt: run.createdAt,
    updatedAt: run.updatedAt,
  };
}

function formatPaceMinPerKm(secondsPerKm: number | null): string | null {
  if (!secondsPerKm || secondsPerKm <= 0) {
    return null;
  }
  const minutes = Math.floor(secondsPerKm / 60);
  const seconds = Math.round(secondsPerKm - minutes * 60);
  return `${minutes}:${String(seconds).padStart(2, '0')}/km`;
}

interface RunSummaryPushPayload {
  title: string;
  body: string;
  data: Record<string, unknown>;
}

interface RunSummaryPushContext {
  userId: Types.ObjectId;
  runId: Types.ObjectId;
  durationSeconds: number;
  distanceMeters: number;
  averagePaceSecondsPerKm: number | null;
  // Avg HR isn't tracked on the Run model today (no HR field on RunSchema).
  // Plumbed through so once #21 / external HR sources land, the body can
  // append "(avg HR 154)" without a second deploy.
  averageHeartRateBpm?: number | null;
}

export function buildRunSummaryPushPayload(
  ctx: RunSummaryPushContext,
): RunSummaryPushPayload {
  const km = Math.round((ctx.distanceMeters / 1_000) * 10) / 10;
  const pace = formatPaceMinPerKm(ctx.averagePaceSecondsPerKm);
  const durationMin = Math.max(1, Math.round(ctx.durationSeconds / 60));
  const headline = pace
    ? `${km} km in ${pace}`
    : `${km} km in ${durationMin} min`;
  const hrSuffix =
    typeof ctx.averageHeartRateBpm === 'number' && ctx.averageHeartRateBpm > 0
      ? ` (avg HR ${Math.round(ctx.averageHeartRateBpm)})`
      : '';

  return {
    title: 'Run complete!',
    body: `${headline}${hrSuffix}`,
    data: {
      type: 'run_summary',
      runId: String(ctx.runId),
      durationSec: ctx.durationSeconds,
      distanceMeters: Math.round(ctx.distanceMeters),
      ...(ctx.averagePaceSecondsPerKm
        ? { averagePaceSecondsPerKm: ctx.averagePaceSecondsPerKm }
        : {}),
      ...(typeof ctx.averageHeartRateBpm === 'number'
        ? { averageHeartRateBpm: Math.round(ctx.averageHeartRateBpm) }
        : {}),
    },
  };
}

/**
 * Pure skip-decision helper for the run summary push. Same shape as the
 * workout side so tests can hit identical assertions.
 */
export function shouldSkipRunSummaryPush(args: {
  durationSeconds: number;
  distanceMeters: number;
  source: string;
  preferences: {
    pushEnabled?: boolean;
    workoutSummaryPushDisabled?: boolean;
  } | null | undefined;
}): string | null {
  const prefs = args.preferences ?? {};
  if (prefs.pushEnabled === false) {
    return 'push_disabled';
  }
  if (prefs.workoutSummaryPushDisabled === true) {
    return 'workout_summary_disabled';
  }
  if (args.source === 'manual') {
    return 'manual_or_backfill';
  }
  if (
    args.durationSeconds < RUN_SUMMARY_PUSH_MIN_DURATION_SECONDS
    && args.distanceMeters < RUN_SUMMARY_PUSH_MIN_DISTANCE_METERS
  ) {
    return 'too_short';
  }
  if (args.distanceMeters <= 0 && args.durationSeconds <= 0) {
    return 'no_metrics';
  }
  return null;
}

async function maybeEnqueueRunSummaryPush(
  run: {
    _id: Types.ObjectId;
    userId: Types.ObjectId;
    durationSeconds: number;
    distanceMeters: number;
    averagePaceSecondsPerKm: number | null;
    source: string;
  },
  requestId?: string,
): Promise<void> {
  try {
    const userDoc = await User.findById(run.userId)
      .select({ preferences: 1 })
      .lean();
    const preferences = userDoc?.preferences ?? null;

    const skip = shouldSkipRunSummaryPush({
      durationSeconds: run.durationSeconds,
      distanceMeters: run.distanceMeters,
      source: run.source,
      preferences,
    });
    if (skip) {
      logger.info('Run summary push skipped', {
        correlationId: requestId,
        runId: String(run._id),
        userId: String(run.userId),
        reason: skip,
      });
      return;
    }

    const payload = buildRunSummaryPushPayload({
      userId: run.userId,
      runId: run._id,
      durationSeconds: run.durationSeconds,
      distanceMeters: run.distanceMeters,
      averagePaceSecondsPerKm: run.averagePaceSecondsPerKm,
    });

    await enqueuePushNotification({
      userId: String(run.userId),
      type: 'run_summary',
      title: payload.title,
      body: payload.body,
      data: payload.data,
      dedupeKey: `run-summary:${String(run._id)}`,
    });
  } catch (err) {
    logger.warn('Run summary push enqueue failed (non-fatal)', {
      correlationId: requestId,
      runId: String(run._id),
      userId: String(run.userId),
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

function serializeRunDetail(run: Record<string, any>) {
  const routePoints = normalizeRoutePoints(run.routePoints);
  const summary = serializeRunSummary({
    ...run,
    routePoints,
  });

  return {
    ...summary,
    route: {
      ...summary.route,
      points: routePoints.map((point) => ({
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: point.timestamp,
        altitudeMeters: point.altitudeMeters,
        horizontalAccuracyMeters: point.horizontalAccuracyMeters,
        speedMetersPerSecond: point.speedMetersPerSecond,
      })),
    },
  };
}

router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit as string, 10) || 20));
    const skip = (page - 1) * limit;
    const filter = { userId };

    const [runs, total] = await Promise.all([
      Run.find(filter)
        .sort({ startedAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      Run.countDocuments(filter),
    ]);

    successResponse(
      res,
      runs.map(serializeRunSummary),
      StatusCodes.OK,
      {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    );
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list runs',
      (error as Error).message,
    );
  }
});

router.get('/active', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);

    const activeRun = await Run.findOne({
      userId,
      endedAt: null,
    })
      .sort({ startedAt: -1 })
      .lean();

    successResponse(res, activeRun ? serializeRunDetail(activeRun) : null);
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load active run',
      (error as Error).message,
    );
  }
});

router.post(
  '/',
  isAuthenticated,
  validateBody(startRunSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const { startedAt, source, notes, routePoints } = req.body as StartRunBody;

      const activeRun = await Run.findOne({
        userId,
        endedAt: null,
      }).lean();

      if (activeRun) {
        errorResponse(
          res,
          StatusCodes.CONFLICT,
          'An active run already exists',
          { activeRunId: String(activeRun._id) },
        );
        return;
      }

      const normalizedPoints = normalizeRoutePoints(routePoints);

      // Backlog item #9 — runs are *always* HKWorkoutActivityType.running
      // for auto-attach purposes. Explicit null from the client means
      // "skip"; explicit id wins over the default; otherwise fall through
      // to the user's `running` default.
      const { gearId: requestedGearId, gearIds: requestedGearIds } = req.body as StartRunBody;
      let primaryGearId: Types.ObjectId | null = null;
      let autoAssigned = false;

      if (requestedGearId === null) {
        primaryGearId = null;
      } else if (requestedGearId && Types.ObjectId.isValid(requestedGearId)) {
        primaryGearId = new Types.ObjectId(requestedGearId);
      } else {
        const defaultGear = await resolveDefaultGear(userId, 'running');
        if (defaultGear) {
          primaryGearId = defaultGear._id;
          autoAssigned = true;
        }
      }

      const additionalGearIds: Types.ObjectId[] =
        Array.isArray(requestedGearIds) && requestedGearIds.length > 0
          ? requestedGearIds
              .filter((id): id is string => typeof id === 'string' && Types.ObjectId.isValid(id))
              .map((id) => new Types.ObjectId(id))
          : primaryGearId
            ? [primaryGearId]
            : [];

      const run = await Run.create({
        userId,
        gearId: primaryGearId,
        gearIds: additionalGearIds,
        startedAt: startedAt ? new Date(startedAt) : new Date(),
        source,
        notes: notes ?? null,
        routePoints: normalizedPoints,
        distanceMeters: computeDistanceMeters(normalizedPoints),
        durationSeconds: 0,
        averagePaceSecondsPerKm: null,
      });

      if (autoAssigned && primaryGearId) {
        await logAutoGearAssigned({
          userId,
          gearId: primaryGearId,
          activityType: 'running',
          runId: run._id,
        });
      }

      successResponse(res, serializeRunDetail(run.toObject()), StatusCodes.CREATED);
    } catch (error) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to start run',
        (error as Error).message,
      );
    }
  },
);

router.get('/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const runId = new Types.ObjectId(req.params.id as string);

    const run = await Run.findOne({
      _id: runId,
      userId,
    }).lean();

    if (!run) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Run not found');
      return;
    }

    successResponse(res, serializeRunDetail(run));
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load run',
      (error as Error).message,
    );
  }
});

router.post(
  '/:id/complete',
  isAuthenticated,
  validateBody(completeRunSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const runId = new Types.ObjectId(req.params.id as string);
      const { endedAt, distanceMeters, notes, routePoints } = req.body as CompleteRunBody;

      const run = await Run.findOne({
        _id: runId,
        userId,
      });

      if (!run) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Run not found');
        return;
      }

      if (run.endedAt) {
        errorResponse(res, StatusCodes.CONFLICT, 'Run is already completed');
        return;
      }

      const completedAt = endedAt ? new Date(endedAt) : new Date();
      if (completedAt.getTime() < run.startedAt.getTime()) {
        errorResponse(
          res,
          StatusCodes.BAD_REQUEST,
          'endedAt must be greater than or equal to startedAt',
        );
        return;
      }

      const normalizedPoints = routePoints ? normalizeRoutePoints(routePoints) : normalizeRoutePoints(run.routePoints);
      const resolvedDistanceMeters = distanceMeters ?? computeDistanceMeters(normalizedPoints);
      const resolvedDurationSeconds = computeDurationSeconds(run.startedAt, completedAt);

      run.endedAt = completedAt;
      run.routePoints = normalizedPoints;
      run.distanceMeters = roundToSingleDecimal(resolvedDistanceMeters);
      run.durationSeconds = resolvedDurationSeconds;
      run.averagePaceSecondsPerKm = computeAveragePaceSecondsPerKm(
        run.distanceMeters,
        run.durationSeconds,
      );

      if (notes !== undefined) {
        run.notes = notes;
      }

      await run.save();

      // Backlog item #9 — accrue mileage on attached gear (shoes typically).
      // We pass distanceMeters to let the helper translate to miles/km based
      // on the gear's `unit` field; sessions-unit gear gets +1.
      const targets = new Set<string>();
      if (run.gearId) {
        targets.add(String(run.gearId));
      }
      for (const id of run.gearIds ?? []) {
        targets.add(String(id));
      }
      for (const idStr of targets) {
        if (!Types.ObjectId.isValid(idStr)) {
          continue;
        }
        await incrementGearForWorkoutMetrics(
          new Types.ObjectId(idStr),
          userId,
          {
            distanceMeters: run.distanceMeters,
            durationSeconds: run.durationSeconds,
          },
        );
      }

      // Best-effort summary push (item #27). The earlier `run.endedAt`
      // guard above already prevents double-completion, so we don't need
      // a separate first-completion check here.
      await maybeEnqueueRunSummaryPush(
        {
          _id: run._id,
          userId: run.userId,
          durationSeconds: run.durationSeconds,
          distanceMeters: run.distanceMeters,
          averagePaceSecondsPerKm: run.averagePaceSecondsPerKm,
          source: run.source,
        },
        req.requestId,
      );

      successResponse(res, serializeRunDetail(run.toObject()));
    } catch (error) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to complete run',
        (error as Error).message,
      );
    }
  },
);

export default router;
