import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { Workout } from '../../models/Workout.js';
import { GymSession } from '../../models/GymSession.js';
import { Run } from '../../models/Run.js';
import { Device } from '../../models/Device.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

const DAY_MS = 24 * 60 * 60 * 1000;
const workoutSetSchema = z.object({
  reps: z.number().int().min(0).max(999),
  weightKg: z.number().finite().min(0).max(1000),
});

const workoutExerciseSchema = z.object({
  name: z.string().trim().min(1).max(120),
  sets: z.array(workoutSetSchema).default([]),
});

const createWorkoutSchema = z.object({
  name: z.string().trim().min(1).max(120),
  gymId: z.string().trim().min(1).optional(),
  startedAt: z.string().datetime(),
  endedAt: z.string().datetime().optional(),
  notes: z.string().trim().max(4000).optional(),
  source: z.enum(['manual', 'apple_health']).optional().default('manual'),
  exercises: z.array(workoutExerciseSchema).default([]),
}).superRefine((value, ctx) => {
  if (value.endedAt && new Date(value.endedAt) < new Date(value.startedAt)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['endedAt'],
      message: 'endedAt must be greater than or equal to startedAt',
    });
  }
});

const updateWorkoutSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  gymId: z.union([z.string().trim().min(1), z.null()]).optional(),
  startedAt: z.string().datetime().optional(),
  endedAt: z.union([z.string().datetime(), z.null()]).optional(),
  notes: z.union([z.string().trim().max(4000), z.null()]).optional(),
  source: z.enum(['manual', 'apple_health']).optional(),
  exercises: z.array(workoutExerciseSchema).optional(),
}).superRefine((value, ctx) => {
  if (value.startedAt && value.endedAt && new Date(value.endedAt) < new Date(value.startedAt)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['endedAt'],
      message: 'endedAt must be greater than or equal to startedAt',
    });
  }
});

const completeWorkoutSchema = z.object({
  endedAt: z.string().datetime().optional(),
});

type CreateWorkoutBody = z.infer<typeof createWorkoutSchema>;
type UpdateWorkoutBody = z.infer<typeof updateWorkoutSchema>;
type CompleteWorkoutBody = z.infer<typeof completeWorkoutSchema>;

function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function startOfUtcWeek(date: Date): Date {
  const dayStart = startOfUtcDay(date);
  const dayOffset = (dayStart.getUTCDay() + 6) % 7;
  dayStart.setUTCDate(dayStart.getUTCDate() - dayOffset);
  return dayStart;
}

function startOfUtcMonth(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
}

function addUtcDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setUTCDate(next.getUTCDate() + days);
  return next;
}

function dateKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function roundToSingleDecimal(value: number): number {
  return Math.round(value * 10) / 10;
}

function computeDurationMinutes(startedAt: Date, endedAt: Date | null): number {
  if (!endedAt) {
    return 0;
  }

  const durationMs = endedAt.getTime() - startedAt.getTime();
  return Math.max(0, Math.round(durationMs / 60_000));
}

function computeDurationSeconds(startedAt: Date, endedAt: Date | null): number {
  if (!endedAt) {
    return 0;
  }

  const durationMs = endedAt.getTime() - startedAt.getTime();
  return Math.max(0, Math.round(durationMs / 1000));
}

function computeAveragePaceSecondsPerKm(distanceMeters: number, durationSeconds: number): number | null {
  if (distanceMeters <= 0 || durationSeconds <= 0) {
    return null;
  }

  return Math.round(durationSeconds / (distanceMeters / 1000));
}

function parseOptionalObjectId(value: string | null | undefined): Types.ObjectId | null {
  if (!value) {
    return null;
  }
  return Types.ObjectId.isValid(value) ? new Types.ObjectId(value) : null;
}

function serializeWorkout(workout: Record<string, any>) {
  const populatedGym =
    workout.gymId
    && typeof workout.gymId === 'object'
    && 'name' in workout.gymId
      ? workout.gymId
      : null;
  const startedAt = workout.startedAt instanceof Date ? workout.startedAt : new Date(workout.startedAt);
  const endedAt =
    workout.endedAt instanceof Date || workout.endedAt === null
      ? workout.endedAt
      : new Date(workout.endedAt);
  const durationMinutes = computeDurationMinutes(startedAt, endedAt) || workout.durationMinutes || 0;

  return {
    _id: String(workout._id),
    name: workout.name,
    gymId: populatedGym ? String(populatedGym._id) : workout.gymId ? String(workout.gymId) : null,
    gymName: populatedGym?.name ?? null,
    startedAt,
    endedAt,
    durationMinutes,
    durationSeconds: durationMinutes * 60,
    exerciseCount: Array.isArray(workout.exercises) ? workout.exercises.length : 0,
    exercises: Array.isArray(workout.exercises)
      ? workout.exercises.map((exercise: Record<string, any>) => ({
          name: exercise.name,
          sets: Array.isArray(exercise.sets)
            ? exercise.sets.map((set: Record<string, any>) => ({
                reps: set.reps,
                weightKg: set.weightKg,
              }))
            : [],
        }))
      : [],
    notes: workout.notes ?? null,
    source: workout.source,
    createdAt: workout.createdAt,
    updatedAt: workout.updatedAt,
  };
}

function buildStreaks(activityDates: Set<string>, referenceDate: Date) {
  if (activityDates.size === 0) {
    return { currentDays: 0, longestDays: 0 };
  }

  const sortedEpochDays = [...activityDates]
    .map((key) => Math.floor(new Date(`${key}T00:00:00.000Z`).getTime() / DAY_MS))
    .sort((a, b) => a - b);

  let longestDays = 1;
  let runningLongest = 1;
  for (let index = 1; index < sortedEpochDays.length; index += 1) {
    if (sortedEpochDays[index] === sortedEpochDays[index - 1] + 1) {
      runningLongest += 1;
    } else {
      runningLongest = 1;
    }
    longestDays = Math.max(longestDays, runningLongest);
  }

  const referenceEpoch = Math.floor(startOfUtcDay(referenceDate).getTime() / DAY_MS);
  const latestEpoch = sortedEpochDays[sortedEpochDays.length - 1];

  if (latestEpoch < referenceEpoch - 1) {
    return { currentDays: 0, longestDays };
  }

  let currentDays = 1;
  for (let index = sortedEpochDays.length - 2; index >= 0; index -= 1) {
    if (sortedEpochDays[index] === sortedEpochDays[index + 1] - 1) {
      currentDays += 1;
    } else {
      break;
    }
  }

  return { currentDays, longestDays };
}

function buildWeekdayDistribution(completedWorkouts: Array<{ startedAt: Date }>) {
  const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const counts = Array.from({ length: labels.length }, () => 0);

  for (const workout of completedWorkouts) {
    counts[workout.startedAt.getUTCDay()] += 1;
  }

  return labels.map((label, index) => ({
    label,
    count: counts[index],
  }));
}

function buildHourDistribution(completedWorkouts: Array<{ startedAt: Date }>) {
  const counts = Array.from({ length: 24 }, () => 0);

  for (const workout of completedWorkouts) {
    counts[workout.startedAt.getUTCHours()] += 1;
  }

  return counts.map((count, hour) => ({
    hour,
    label: `${String(hour).padStart(2, '0')}:00`,
    count,
  }));
}

function serializeRunMetricsCard(run: Record<string, any>) {
  const startedAt = run.startedAt instanceof Date ? run.startedAt : new Date(run.startedAt);
  const endedAt =
    run.endedAt instanceof Date || run.endedAt === null
      ? run.endedAt
      : new Date(run.endedAt);
  const routePointCount = Array.isArray(run.routePoints) ? run.routePoints.length : 0;
  const durationSeconds = typeof run.durationSeconds === 'number'
    ? run.durationSeconds
    : computeDurationSeconds(startedAt, endedAt);
  const distanceMeters = typeof run.distanceMeters === 'number'
    ? roundToSingleDecimal(run.distanceMeters)
    : 0;
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
    source: run.source ?? 'ios',
    routePointCount,
  };
}

function serializeDeviceMetricsCard(device: Record<string, any>) {
  return {
    _id: String(device._id),
    name: device.name,
    nickname: device.nickname ?? null,
    type: device.type,
    status: device.status,
    isFavorite: device.isFavorite === true,
    isMonitoring: device.monitoringEnabled === true,
    signalStrength: typeof device.lastSignalStrength === 'number' ? device.lastSignalStrength : null,
    lastSeenAt: device.lastSeenAt ?? null,
  };
}

function buildDistanceTrend(thisWeekDistanceMeters: number, lastWeekDistanceMeters: number) {
  const deltaMeters = roundToSingleDecimal(thisWeekDistanceMeters - lastWeekDistanceMeters);
  const deltaPercent = lastWeekDistanceMeters > 0
    ? roundToSingleDecimal((deltaMeters / lastWeekDistanceMeters) * 100)
    : thisWeekDistanceMeters > 0
      ? null
      : 0;
  const direction =
    Math.abs(deltaMeters) < 0.1
      ? 'flat'
      : deltaMeters > 0
        ? 'up'
        : 'down';

  return {
    direction,
    deltaMeters,
    deltaPercent,
    thisWeekDistanceMeters,
    lastWeekDistanceMeters,
  };
}

// GET /workouts/metrics/overview
router.get('/metrics/overview', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const now = new Date();
    const start30d = addUtcDays(startOfUtcDay(now), -29);
    const startOfWeek = startOfUtcWeek(now);
    const startOfLastWeek = addUtcDays(startOfWeek, -7);
    const startOfMonth = startOfUtcMonth(now);

    const [
      sessions30d,
      sessionsThisWeek,
      sessionsThisMonth,
      allSessions,
      allCompletedWorkouts,
      recentWorkouts,
      allCompletedRuns,
      recentRuns,
      activeRunCount,
      devices,
    ] =
      await Promise.all([
        GymSession.find({
          userId,
          startedAt: { $gte: start30d },
          endedAt: { $ne: null },
        })
          .select('startedAt durationMinutes')
          .lean(),
        GymSession.find({
          userId,
          startedAt: { $gte: startOfWeek },
          endedAt: { $ne: null },
        })
          .select('startedAt')
          .lean(),
        GymSession.find({
          userId,
          startedAt: { $gte: startOfMonth },
          endedAt: { $ne: null },
        })
          .select('startedAt')
          .lean(),
        GymSession.find({ userId }).select('startedAt').lean(),
        Workout.find({
          userId,
          endedAt: { $ne: null },
        })
          .select('startedAt durationMinutes exercises endedAt createdAt updatedAt name source notes gymId')
          .populate('gymId', 'name')
          .sort({ startedAt: -1 })
          .lean(),
        Workout.find({
          userId,
          endedAt: { $ne: null },
        })
          .select('startedAt durationMinutes exercises endedAt createdAt updatedAt name source notes gymId')
          .populate('gymId', 'name')
          .sort({ startedAt: -1 })
          .limit(6)
          .lean(),
        Run.find({
          userId,
          endedAt: { $ne: null },
        })
          .select('startedAt endedAt durationSeconds distanceMeters averagePaceSecondsPerKm routePoints source createdAt updatedAt')
          .sort({ startedAt: -1 })
          .lean(),
        Run.find({ userId })
          .select('startedAt endedAt durationSeconds distanceMeters averagePaceSecondsPerKm routePoints source createdAt updatedAt')
          .sort({ startedAt: -1 })
          .limit(6)
          .lean(),
        Run.countDocuments({
          userId,
          endedAt: null,
        }),
        Device.find({ userId })
          .select('name nickname type status isFavorite monitoringEnabled lastSeenAt lastSignalStrength createdAt updatedAt')
          .sort({ isFavorite: -1, updatedAt: -1, createdAt: -1 })
          .lean(),
      ]);

    const recentSerialized = recentWorkouts.map((workout) => serializeWorkout(workout));
    const activityDates = new Set<string>([
      ...allSessions.map((session) => dateKey(session.startedAt)),
      ...allCompletedWorkouts.map((workout) => dateKey(workout.startedAt)),
    ]);
    const streaks = buildStreaks(activityDates, now);
    const averageSessionDurationMinutes30d =
      sessions30d.length > 0
        ? roundToSingleDecimal(
            sessions30d.reduce((total, session) => total + (session.durationMinutes || 0), 0)
            / sessions30d.length,
          )
        : 0;
    const workoutsThisMonth = allCompletedWorkouts.filter((workout) => workout.startedAt >= startOfMonth);
    const totalWorkoutMinutesThisMonth = workoutsThisMonth.reduce(
      (total, workout) => total + (workout.durationMinutes || 0),
      0,
    );
    const runs30d = allCompletedRuns.filter((run) => run.startedAt >= start30d);
    const runsThisWeek = allCompletedRuns.filter((run) => run.startedAt >= startOfWeek);
    const runsLastWeek = allCompletedRuns.filter(
      (run) => run.startedAt >= startOfLastWeek && run.startedAt < startOfWeek,
    );
    const totalDistanceMeters = roundToSingleDecimal(
      allCompletedRuns.reduce((total, run) => total + (run.distanceMeters || 0), 0),
    );
    const totalDistanceMeters30d = roundToSingleDecimal(
      runs30d.reduce((total, run) => total + (run.distanceMeters || 0), 0),
    );
    const thisWeekDistanceMeters = roundToSingleDecimal(
      runsThisWeek.reduce((total, run) => total + (run.distanceMeters || 0), 0),
    );
    const lastWeekDistanceMeters = roundToSingleDecimal(
      runsLastWeek.reduce((total, run) => total + (run.distanceMeters || 0), 0),
    );
    const averageRunDistanceMeters30d =
      runs30d.length > 0 ? roundToSingleDecimal(totalDistanceMeters30d / runs30d.length) : 0;
    const deviceCards = devices.map(serializeDeviceMetricsCard);
    const favoriteDevices = devices.filter((device) => device.isFavorite === true).length;
    const monitoringDevices = devices.filter((device) => device.monitoringEnabled === true).length;
    const lostDevices = devices.filter((device) => device.status === 'lost').length;

    successResponse(res, {
      summary: {
        averageSessionDurationMinutes30d,
        sessionsThisWeek: sessionsThisWeek.length,
        sessionsThisMonth: sessionsThisMonth.length,
        completedWorkouts: allCompletedWorkouts.length,
        workoutsThisMonth: workoutsThisMonth.length,
        totalWorkoutMinutesThisMonth,
      },
      streaks,
      distributions: {
        byWeekday: buildWeekdayDistribution(allCompletedWorkouts),
        byHour: buildHourDistribution(allCompletedWorkouts),
      },
      runSummary: {
        completedRuns: allCompletedRuns.length,
        activeRuns: activeRunCount,
        totalDistanceMeters,
        totalDistanceMeters30d,
        averageRunDistanceMeters30d,
      },
      runTrend: buildDistanceTrend(thisWeekDistanceMeters, lastWeekDistanceMeters),
      deviceSummary: {
        totalDevices: devices.length,
        favorites: favoriteDevices,
        monitoring: monitoringDevices,
        lost: lostDevices,
      },
      devices: deviceCards,
      recentRuns: recentRuns.map(serializeRunMetricsCard),
      recentWorkouts: recentSerialized,
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load workout metrics overview',
      (err as Error).message,
    );
  }
});

// GET /workouts
router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit as string, 10) || 20));
    const skip = (page - 1) * limit;

    const [workouts, total] = await Promise.all([
      Workout.find({ userId })
        .populate('gymId', 'name')
        .sort({ startedAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      Workout.countDocuments({ userId }),
    ]);

    successResponse(
      res,
      workouts.map((workout) => serializeWorkout(workout)),
      StatusCodes.OK,
      {
        page,
        limit,
        total,
        hasMore: skip + workouts.length < total,
      },
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list workouts',
      (err as Error).message,
    );
  }
});

// POST /workouts
router.post(
  '/',
  isAuthenticated,
  validateBody(createWorkoutSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const body = req.body as CreateWorkoutBody;
      const gymId = parseOptionalObjectId(body.gymId);

      if (body.gymId && !gymId) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid gymId');
        return;
      }

      const startedAt = new Date(body.startedAt);
      const endedAt = body.endedAt ? new Date(body.endedAt) : null;

      const workout = await Workout.create({
        userId,
        gymId,
        name: body.name,
        startedAt,
        endedAt,
        durationMinutes: computeDurationMinutes(startedAt, endedAt),
        exercises: body.exercises,
        notes: body.notes,
        source: body.source ?? 'manual',
      });

      const createdWorkout = await Workout.findById(workout._id)
        .populate('gymId', 'name')
        .lean();

      successResponse(res, serializeWorkout(createdWorkout ?? workout.toObject()), StatusCodes.CREATED);
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to create workout',
        (err as Error).message,
      );
    }
  },
);

// GET /workouts/:id
router.get('/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const workoutId = req.params.id as string;

    if (!Types.ObjectId.isValid(workoutId)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid workout id');
      return;
    }

    const workout = await Workout.findOne({
      _id: new Types.ObjectId(workoutId),
      userId,
    })
      .populate('gymId', 'name')
      .lean();

    if (!workout) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Workout not found');
      return;
    }

    successResponse(res, serializeWorkout(workout));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to get workout',
      (err as Error).message,
    );
  }
});

// PATCH /workouts/:id
router.patch(
  '/:id',
  isAuthenticated,
  validateBody(updateWorkoutSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const workoutId = req.params.id as string;
      const body = req.body as UpdateWorkoutBody;

      if (!Types.ObjectId.isValid(workoutId)) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid workout id');
        return;
      }

      const workout = await Workout.findOne({
        _id: new Types.ObjectId(workoutId),
        userId,
      });

      if (!workout) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Workout not found');
        return;
      }

      if (body.gymId !== undefined) {
        if (body.gymId === null) {
          workout.gymId = null;
        } else {
          const gymId = parseOptionalObjectId(body.gymId);
          if (!gymId) {
            errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid gymId');
            return;
          }
          workout.gymId = gymId;
        }
      }

      if (body.name !== undefined) {
        workout.name = body.name;
      }

      if (body.startedAt !== undefined) {
        workout.startedAt = new Date(body.startedAt);
      }

      if (body.endedAt !== undefined) {
        workout.endedAt = body.endedAt ? new Date(body.endedAt) : null;
      }

      if (body.notes !== undefined) {
        workout.notes = body.notes ?? undefined;
      }

      if (body.source !== undefined) {
        workout.source = body.source;
      }

      if (body.exercises !== undefined) {
        workout.exercises = body.exercises;
      }

      workout.durationMinutes = computeDurationMinutes(workout.startedAt, workout.endedAt);
      await workout.save();

      const updatedWorkout = await Workout.findById(workout._id)
        .populate('gymId', 'name')
        .lean();

      successResponse(res, serializeWorkout(updatedWorkout ?? workout.toObject()));
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update workout',
        (err as Error).message,
      );
    }
  },
);

// DELETE /workouts/:id
router.delete('/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const workoutId = req.params.id as string;

    if (!Types.ObjectId.isValid(workoutId)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid workout id');
      return;
    }

    const deletedWorkout = await Workout.findOneAndDelete({
      _id: new Types.ObjectId(workoutId),
      userId,
    }).lean();

    if (!deletedWorkout) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Workout not found');
      return;
    }

    successResponse(res, { _id: String(deletedWorkout._id), deleted: true });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to delete workout',
      (err as Error).message,
    );
  }
});

// POST /workouts/:id/complete
router.post(
  '/:id/complete',
  isAuthenticated,
  validateBody(completeWorkoutSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const workoutId = req.params.id as string;
      const body = req.body as CompleteWorkoutBody;

      if (!Types.ObjectId.isValid(workoutId)) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid workout id');
        return;
      }

      const workout = await Workout.findOne({
        _id: new Types.ObjectId(workoutId),
        userId,
      });

      if (!workout) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Workout not found');
        return;
      }

      const endedAt = body.endedAt ? new Date(body.endedAt) : new Date();
      if (endedAt < workout.startedAt) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'endedAt must be greater than or equal to startedAt');
        return;
      }

      workout.endedAt = endedAt;
      workout.durationMinutes = computeDurationMinutes(workout.startedAt, endedAt);
      await workout.save();

      const completedWorkout = await Workout.findById(workout._id)
        .populate('gymId', 'name')
        .lean();

      // TODO(gemini-insights): once PR #69 (feat/workout-summary-push-item-27)
      // merges, wire `generateWorkoutInsight({...})` from
      // `../../services/geminiClient` into the workout-summary push path here
      // and append the returned string (if non-null) to the push body,
      // keeping total body < 230 chars. The geminiClient is feature-flagged
      // via GEMINI_INSIGHTS_ENABLED and fails closed, so this wire-up is
      // safe to add without further guarding.
      successResponse(res, serializeWorkout(completedWorkout ?? workout.toObject()));
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to complete workout',
        (err as Error).message,
      );
    }
  },
);

export default router;
