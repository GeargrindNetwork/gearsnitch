import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { Run, type IRunPoint } from '../../models/Run.js';
import { successResponse, errorResponse } from '../../utils/response.js';

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

const startRunSchema = z.object({
  startedAt: z.string().datetime().optional(),
  source: z.enum(['ios', 'manual']).optional().default('ios'),
  notes: z.string().trim().max(2_000).optional(),
  routePoints: z.array(runPointSchema).optional().default([]),
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
    route: {
      pointCount: routePoints.length,
      bounds: computeBounds(routePoints),
    },
    createdAt: run.createdAt,
    updatedAt: run.updatedAt,
  };
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
      const run = await Run.create({
        userId,
        startedAt: startedAt ? new Date(startedAt) : new Date(),
        source,
        notes: notes ?? null,
        routePoints: normalizedPoints,
        distanceMeters: computeDistanceMeters(normalizedPoints),
        durationSeconds: 0,
        averagePaceSecondsPerKm: null,
      });

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
