import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { EventLog, EVENT_TYPES } from '../../models/EventLog.js';
import { getRedisClient } from '../../loaders/redis.js';

const router = Router();

// ---------------------------------------------------------------------------
// Validation Schemas
// ---------------------------------------------------------------------------

const eventItemSchema = z.object({
  eventType: z.enum(EVENT_TYPES),
  metadata: z.record(z.unknown()).optional(),
  source: z.enum(['ios', 'web', 'system', 'widget', 'watchos']).optional().default('ios'),
  timestamp: z.string().datetime().optional(),
});

const batchEventSchema = z.object({
  events: z
    .array(eventItemSchema)
    .min(1, 'At least one event is required')
    .max(50, 'Maximum 50 events per batch'),
});

// ---------------------------------------------------------------------------
// POST /events — Log events (batch support)
// ---------------------------------------------------------------------------

router.post(
  '/',
  isAuthenticated,
  validateBody(batchEventSchema),
  async (req: Request, res: Response) => {
    try {
      const user = req.user as JwtPayload;
      const userId = new Types.ObjectId(user.sub);
      const { events } = req.body as z.infer<typeof batchEventSchema>;

      const docs = events.map((e) => ({
        userId,
        eventType: e.eventType,
        metadata: e.metadata,
        source: e.source,
        timestamp: e.timestamp ? new Date(e.timestamp) : new Date(),
      }));

      // Write to MongoDB
      const inserted = await EventLog.insertMany(docs);

      // Write to Redis stream for real-time consumers
      try {
        const redis = getRedisClient();
        const streamKey = `events:${user.sub}`;
        const pipeline = redis.pipeline();
        for (const e of docs) {
          pipeline.xadd(
            streamKey,
            '*',
            'eventType',
            e.eventType,
            'source',
            e.source ?? 'ios',
            'timestamp',
            e.timestamp.toISOString(),
            'metadata',
            JSON.stringify(e.metadata ?? {}),
          );
        }
        await pipeline.exec();
      } catch {
        // Redis stream write is best-effort; MongoDB is the source of truth
      }

      successResponse(res, { inserted: inserted.length }, StatusCodes.CREATED);
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to log events',
        (err as Error).message,
      );
    }
  },
);

// ---------------------------------------------------------------------------
// GET /events — List events (paginated, filterable by type)
// ---------------------------------------------------------------------------

router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string) || 50));
    const skip = (page - 1) * limit;

    const filter: Record<string, unknown> = {
      userId: new Types.ObjectId(user.sub),
    };

    if (req.query.type) {
      filter.eventType = req.query.type;
    }

    const [events, total] = await Promise.all([
      EventLog.find(filter).sort({ timestamp: -1 }).skip(skip).limit(limit).lean(),
      EventLog.countDocuments(filter),
    ]);

    successResponse(res, events, StatusCodes.OK, {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list events',
      (err as Error).message,
    );
  }
});

export default router;
