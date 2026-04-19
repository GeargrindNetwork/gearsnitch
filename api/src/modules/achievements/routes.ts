import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { getAchievementsWithProgress } from './service.js';

/**
 * Backlog item #39 — achievement badges HTTP surface.
 *
 * `GET /api/v1/achievements/me` returns every catalog badge, marking which
 * are earned (with `earnedAt`) and which are locked (with progress hints).
 * The client renders the full grid so the locked state is self-describing.
 */

const router = Router();

router.get('/me', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const { earned, locked, stats } = await getAchievementsWithProgress(userId);

    successResponse(res, {
      earned: earned.map((e) => ({
        badgeId: e.badgeId,
        earnedAt: e.earnedAt,
        title: e.definition.title,
        description: e.definition.description,
        icon: e.definition.icon,
      })),
      locked: locked.map((l) => ({
        badgeId: l.badgeId,
        title: l.definition.title,
        description: l.definition.description,
        icon: l.definition.icon,
        progress: l.progress,
      })),
      stats: {
        runCount: stats.runCount,
        workoutCount: stats.workoutCount,
        deviceCount: stats.deviceCount,
        subscriptionChargeCount: stats.subscriptionChargeCount,
        totalRunMeters: stats.totalRunMeters,
        currentStreakDays: stats.currentStreakDays,
      },
    });
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load achievements',
      (error as Error).message,
    );
  }
});

export default router;
