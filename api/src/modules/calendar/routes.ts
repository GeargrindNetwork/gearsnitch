import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { GymSession } from '../../models/GymSession.js';
import { Meal } from '../../models/Meal.js';
import { StoreOrder } from '../../models/StoreOrder.js';
import { WaterLog } from '../../models/WaterLog.js';
import { Workout } from '../../models/Workout.js';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface DaySummary {
  gymVisits: number;
  gymMinutes: number;
  mealsLogged: number;
  totalCalories: number;
  purchasesMade: number;
  waterIntakeMl: number;
  workoutsCompleted: number;
}

function monthRange(year: number, month: number): { start: Date; end: Date } {
  const start = new Date(Date.UTC(year, month - 1, 1));
  const end = new Date(Date.UTC(year, month, 1));
  return { start, end };
}

function dayRange(dateStr: string): { start: Date; end: Date } {
  const start = new Date(`${dateStr}T00:00:00.000Z`);
  const end = new Date(`${dateStr}T23:59:59.999Z`);
  return { start, end };
}

function dateKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// ---------------------------------------------------------------------------
// GET /calendar/month?year=2026&month=4 — Monthly activity summary
// ---------------------------------------------------------------------------

router.get('/month', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);

    const year = parseInt(req.query.year as string);
    const month = parseInt(req.query.month as string);

    if (!year || !month || month < 1 || month > 12) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Valid year and month (1-12) are required');
      return;
    }

    const { start, end } = monthRange(year, month);

    const [gymSessions, meals, orders, waterLogs, workouts] = await Promise.all([
      GymSession.find({
        userId,
        startedAt: { $gte: start, $lt: end },
      })
        .select('startedAt durationMinutes')
        .lean(),
      Meal.find({
        userId,
        date: {
          $gte: dateKey(start),
          $lt: dateKey(end),
        },
      })
        .select('date calories')
        .lean(),
      StoreOrder.find({
        userId,
        status: { $in: ['paid', 'fulfilled'] },
        createdAt: { $gte: start, $lt: end },
      })
        .select('createdAt')
        .lean(),
      WaterLog.find({
        userId,
        date: {
          $gte: dateKey(start),
          $lt: dateKey(end),
        },
      })
        .select('date amountMl')
        .lean(),
      Workout.find({
        userId,
        startedAt: { $gte: start, $lt: end },
        endedAt: { $ne: null },
      })
        .select('startedAt')
        .lean(),
    ]);

    // Aggregate by day
    const days: Record<string, DaySummary> = {};

    function ensureDay(key: string): DaySummary {
      if (!days[key]) {
        days[key] = {
          gymVisits: 0,
          gymMinutes: 0,
          mealsLogged: 0,
          totalCalories: 0,
          purchasesMade: 0,
          waterIntakeMl: 0,
          workoutsCompleted: 0,
        };
      }
      return days[key];
    }

    for (const s of gymSessions) {
      const d = ensureDay(dateKey(s.startedAt));
      d.gymVisits += 1;
      d.gymMinutes += s.durationMinutes || 0;
    }

    for (const m of meals) {
      const d = ensureDay(m.date);
      d.mealsLogged += 1;
      d.totalCalories += m.calories || 0;
    }

    for (const o of orders) {
      const d = ensureDay(dateKey(o.createdAt));
      d.purchasesMade += 1;
    }

    for (const w of waterLogs) {
      const d = ensureDay(w.date);
      d.waterIntakeMl += w.amountMl;
    }

    for (const w of workouts) {
      const d = ensureDay(dateKey(w.startedAt));
      d.workoutsCompleted += 1;
    }

    successResponse(res, { days });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load calendar month',
      (err as Error).message,
    );
  }
});

// ---------------------------------------------------------------------------
// GET /calendar/day/:date — Detailed day activity (YYYY-MM-DD)
// ---------------------------------------------------------------------------

router.get('/day/:date', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);
    const date = req.params.date as string;

    // Validate date format
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Date must be YYYY-MM-DD format');
      return;
    }

    const { start, end } = dayRange(date);

    const [sessions, meals, purchases, waterLogs, workouts] = await Promise.all([
      GymSession.find({
        userId,
        startedAt: { $gte: start, $lte: end },
      }).lean(),
      Meal.find({
        userId,
        date,
      }).lean(),
      StoreOrder.find({
        userId,
        status: { $in: ['paid', 'fulfilled'] },
        createdAt: { $gte: start, $lte: end },
      }).lean(),
      WaterLog.find({
        userId,
        date,
      }).lean(),
      Workout.find({
        userId,
        startedAt: { $gte: start, $lte: end },
      }).lean(),
    ]);

    successResponse(res, {
      sessions,
      meals,
      purchases,
      waterLogs,
      workouts,
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load calendar day',
      (err as Error).message,
    );
  }
});

export default router;
