import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { GymSession } from '../../models/GymSession.js';

const router = Router();

// ---------------------------------------------------------------------------
// Validation Schemas
// ---------------------------------------------------------------------------

const startSessionSchema = z.object({
  gymId: z.string().min(1, 'gymId is required'),
  gymName: z.string().optional(),
  source: z.enum(['manual', 'geofence', 'widget']).optional().default('manual'),
  startedAt: z.string().datetime().optional(),
});

const endSessionSchema = z.object({
  endedAt: z.string().datetime().optional(),
});

function serializeSession(session: Record<string, any>) {
  return {
    _id: String(session._id),
    userId: String(session.userId),
    gymId: String(session.gymId),
    gymName: session.gymName ?? null,
    startedAt: session.startedAt?.toISOString?.() ?? session.startedAt,
    endedAt: session.endedAt?.toISOString?.() ?? session.endedAt ?? null,
    durationMinutes: session.durationMinutes ?? 0,
    source: session.source ?? 'manual',
    events: (session.events ?? []).map((ev: any) => ({
      type: ev.type,
      timestamp: ev.timestamp?.toISOString?.() ?? ev.timestamp,
      metadata: ev.metadata,
    })),
    createdAt: session.createdAt?.toISOString?.() ?? session.createdAt,
    updatedAt: session.updatedAt?.toISOString?.() ?? session.updatedAt,
  };
}

// ---------------------------------------------------------------------------
// POST /sessions — Start a gym session
// ---------------------------------------------------------------------------

router.post(
  '/',
  isAuthenticated,
  validateBody(startSessionSchema),
  async (req: Request, res: Response) => {
    try {
      const user = req.user as JwtPayload;
      const { gymId, gymName, source, startedAt } = req.body as z.infer<typeof startSessionSchema>;

      if (!Types.ObjectId.isValid(gymId)) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid gymId');
        return;
      }

      // Check for already-active session
      const active = await GymSession.findOne({
        userId: new Types.ObjectId(user.sub),
        endedAt: null,
      }).lean();

      if (active) {
        errorResponse(
          res,
          StatusCodes.CONFLICT,
          'An active session already exists',
          { activeSessionId: String(active._id) },
        );
        return;
      }

      const session = await GymSession.create({
        userId: new Types.ObjectId(user.sub),
        gymId: new Types.ObjectId(gymId),
        gymName,
        source,
        startedAt: startedAt ? new Date(startedAt) : new Date(),
        events: [{ type: 'session_start', timestamp: new Date() }],
      });

      successResponse(res, serializeSession(session.toObject()), StatusCodes.CREATED);
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to start session',
        (err as Error).message,
      );
    }
  },
);

// ---------------------------------------------------------------------------
// PATCH /sessions/:id/end — End a session
// ---------------------------------------------------------------------------

router.patch(
  '/:id/end',
  isAuthenticated,
  validateBody(endSessionSchema),
  async (req: Request, res: Response) => {
    try {
      const user = req.user as JwtPayload;
      const id = req.params.id as string;

      if (!Types.ObjectId.isValid(id)) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid session id');
        return;
      }

      const { endedAt } = req.body as z.infer<typeof endSessionSchema>;

      const session = await GymSession.findOne({
        _id: new Types.ObjectId(id),
        userId: new Types.ObjectId(user.sub),
      });

      if (!session) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Session not found');
        return;
      }

      if (session.endedAt) {
        errorResponse(res, StatusCodes.CONFLICT, 'Session already ended');
        return;
      }

      const endTime = endedAt ? new Date(endedAt) : new Date();
      const durationMs = endTime.getTime() - session.startedAt.getTime();
      const durationMinutes = Math.round(durationMs / 60_000);

      session.endedAt = endTime;
      session.durationMinutes = durationMinutes;
      session.events.push({ type: 'session_end', timestamp: endTime });
      await session.save();

      successResponse(res, serializeSession(session.toObject()));
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to end session',
        (err as Error).message,
      );
    }
  },
);

// ---------------------------------------------------------------------------
// GET /sessions — List sessions (paginated)
// ---------------------------------------------------------------------------

router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit as string) || 20));
    const skip = (page - 1) * limit;

    const filter = { userId: new Types.ObjectId(user.sub) };

    const [sessions, total] = await Promise.all([
      GymSession.find(filter).sort({ startedAt: -1 }).skip(skip).limit(limit).lean(),
      GymSession.countDocuments(filter),
    ]);

    successResponse(res, sessions.map(serializeSession), StatusCodes.OK, {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list sessions',
      (err as Error).message,
    );
  }
});

// ---------------------------------------------------------------------------
// GET /sessions/active — Get current active session
// ---------------------------------------------------------------------------

router.get('/active', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;

    const session = await GymSession.findOne({
      userId: new Types.ObjectId(user.sub),
      endedAt: null,
    })
      .sort({ startedAt: -1 })
      .lean();

    successResponse(res, session ? serializeSession(session) : null);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to get active session',
      (err as Error).message,
    );
  }
});

// ---------------------------------------------------------------------------
// GET /sessions/:id — Get session detail
// ---------------------------------------------------------------------------

router.get('/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const id = req.params.id as string;

    if (!Types.ObjectId.isValid(id)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid session id');
      return;
    }

    const session = await GymSession.findOne({
      _id: new Types.ObjectId(id),
      userId: new Types.ObjectId(user.sub),
    }).lean();

    if (!session) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Session not found');
      return;
    }

    successResponse(res, serializeSession(session));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to get session',
      (err as Error).message,
    );
  }
});

export default router;
