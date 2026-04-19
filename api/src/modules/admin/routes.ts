import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, hasRole } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { User } from '../../models/User.js';
import { Device } from '../../models/Device.js';
import { GymSession } from '../../models/GymSession.js';
import { Subscription } from '../../models/Subscription.js';
import { HealthMetric } from '../../models/HealthMetric.js';
import { LabAppointment } from '../../models/LabAppointment.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import reconciliationRouter from './reconciliation.js';

const router = Router();

// All admin routes require authentication + admin role
router.use(isAuthenticated, hasRole(['admin']));

// Subscription reconciliation cron admin endpoints.
router.use('/reconciliation', reconciliationRouter);

const updateUserSchema = z.object({
  roles: z.array(z.string()).optional(),
  status: z.enum(['active', 'suspended', 'banned']).optional(),
  displayName: z.string().trim().min(1).max(100).optional(),
});

function serializeUser(user: Record<string, any>) {
  return {
    _id: String(user._id),
    email: user.email ?? null,
    displayName: user.displayName ?? null,
    roles: user.roles ?? ['user'],
    status: user.status ?? 'active',
    subscriptionTier: user.subscriptionTier ?? 'free',
    authProviders: user.authProviders ?? [],
    createdAt: user.createdAt?.toISOString?.() ?? user.createdAt,
    onboardingCompletedAt: user.onboardingCompletedAt?.toISOString?.() ?? null,
    deletedAt: user.deletedAt?.toISOString?.() ?? null,
  };
}

// GET /admin/users — paginated, searchable
router.get('/users', async (req: Request, res: Response) => {
  try {
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 25));
    const skip = (page - 1) * limit;
    const search = (req.query.search as string || '').trim();
    const status = req.query.status as string || '';

    const filter: Record<string, unknown> = {};
    if (search) {
      // Escape regex special characters to prevent NoSQL injection
      const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      filter.$or = [
        { email: { $regex: escaped, $options: 'i' } },
        { displayName: { $regex: escaped, $options: 'i' } },
      ];
    }
    if (status) {
      filter.status = status;
    }

    const [users, total] = await Promise.all([
      User.find(filter)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .select('email displayName roles status subscriptionTier authProviders createdAt onboardingCompletedAt deletedAt')
        .lean(),
      User.countDocuments(filter),
    ]);

    successResponse(res, users.map(serializeUser), StatusCodes.OK, {
      page, limit, total, totalPages: Math.ceil(total / limit),
    });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to list users', (err as Error).message);
  }
});

// GET /admin/stats — dashboard metrics
router.get('/stats', async (_req: Request, res: Response) => {
  try {
    const now = new Date();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    const [
      totalUsers,
      activeUsers30d,
      newUsers7d,
      totalDevices,
      totalSessions,
      activeSessions,
      totalSubscriptions,
      totalHRSamples,
      totalLabAppointments,
    ] = await Promise.all([
      User.countDocuments({ deletedAt: null }),
      User.countDocuments({ deletedAt: null, updatedAt: { $gte: thirtyDaysAgo } }),
      User.countDocuments({ deletedAt: null, createdAt: { $gte: sevenDaysAgo } }),
      Device.countDocuments({}),
      GymSession.countDocuments({}),
      GymSession.countDocuments({ endedAt: null }),
      Subscription.countDocuments({ status: 'active' }),
      HealthMetric.countDocuments({ metricType: 'heart_rate' }),
      LabAppointment.countDocuments({}),
    ]);

    successResponse(res, {
      users: {
        total: totalUsers,
        active30d: activeUsers30d,
        new7d: newUsers7d,
      },
      devices: {
        total: totalDevices,
      },
      sessions: {
        total: totalSessions,
        active: activeSessions,
      },
      subscriptions: {
        active: totalSubscriptions,
      },
      health: {
        heartRateSamples: totalHRSamples,
      },
      labs: {
        totalAppointments: totalLabAppointments,
      },
    });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load admin stats', (err as Error).message);
  }
});

// PATCH /admin/users/:id — update user role/status
router.patch('/users/:id', validateBody(updateUserSchema), async (req: Request, res: Response) => {
  try {
    const userId = req.params.id;
    const body = req.body as z.infer<typeof updateUserSchema>;

    const user = await User.findByIdAndUpdate(
      userId,
      { $set: body },
      { new: true }
    )
      .select('email displayName roles status subscriptionTier authProviders createdAt onboardingCompletedAt deletedAt')
      .lean();

    if (!user) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    successResponse(res, serializeUser(user));
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to update user', (err as Error).message);
  }
});

// DELETE /admin/users/:id — soft delete user
router.delete('/users/:id', async (req: Request, res: Response) => {
  try {
    const userId = req.params.id;

    // Prevent self-deletion
    if (userId === req.user!.sub) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Cannot delete your own admin account');
      return;
    }

    const user = await User.findByIdAndUpdate(
      userId,
      { $set: { status: 'deleted', deletedAt: new Date() } },
      { new: true }
    ).lean();

    if (!user) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    successResponse(res, { deleted: true, userId: String(user._id) });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to delete user', (err as Error).message);
  }
});

export default router;
