import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { errorResponse, successResponse } from '../../utils/response.js';
import { EventLog } from '../../models/EventLog.js';
import { Gym } from '../../models/Gym.js';
import { GymSession } from '../../models/GymSession.js';
import { GymService, GymServiceError } from './gymService.js';

const router = Router();
const gymService = new GymService();

const geoPointSchema = z.object({
  type: z.literal('Point'),
  coordinates: z.tuple([z.number().finite(), z.number().finite()]),
});

const createGymSchema = z.object({
  name: z.string().trim().min(1).max(160),
  location: geoPointSchema,
  radiusMeters: z.coerce.number().positive().max(5000),
  isDefault: z.boolean().optional(),
});

const updateGymSchema = z.object({
  name: z.string().trim().min(1).max(160).optional(),
  location: geoPointSchema.optional(),
  radiusMeters: z.coerce.number().positive().max(5000).optional(),
  isDefault: z.boolean().optional(),
}).refine(
  (body) =>
    body.name !== undefined
    || body.location !== undefined
    || body.radiusMeters !== undefined
    || body.isDefault !== undefined,
  {
    message: 'At least one field must be provided',
  },
);

const gymEventSchema = z.object({
  gymId: z.string().trim().min(1),
  eventType: z.enum(['entry', 'exit']),
  occurredAt: z.coerce.date().optional(),
  latitude: z.number().finite().min(-90).max(90).optional(),
  longitude: z.number().finite().min(-180).max(180).optional(),
  source: z.enum(['ios', 'web', 'system']).optional().default('ios'),
});

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function getRouteParam(req: Request, key: string): string {
  const value = req.params[key];
  return Array.isArray(value) ? value[0] : value;
}

function handleGymError(res: Response, err: unknown, fallbackMessage: string): void {
  if (err instanceof GymServiceError) {
    errorResponse(res, err.statusCode, err.message);
    return;
  }

  errorResponse(
    res,
    StatusCodes.INTERNAL_SERVER_ERROR,
    fallbackMessage,
    err instanceof Error ? err.message : String(err),
  );
}

// GET /gyms
router.get('/', isAuthenticated, async (req, res) => {
  try {
    const gyms = await gymService.listGyms(getUserId(req));
    successResponse(res, gyms);
  } catch (err) {
    handleGymError(res, err, 'Failed to list gyms');
  }
});

// POST /gyms
router.post(
  '/',
  isAuthenticated,
  validateBody(createGymSchema),
  async (req, res) => {
    try {
      const gym = await gymService.createGym(
        getUserId(req),
        req.body as z.infer<typeof createGymSchema>,
      );
      successResponse(res, gym, StatusCodes.CREATED);
    } catch (err) {
      handleGymError(res, err, 'Failed to create gym');
    }
  },
);

// POST /gyms/evaluate
router.post('/evaluate', isAuthenticated, (_req, res) => {
  errorResponse(
    res,
    StatusCodes.NOT_IMPLEMENTED,
    'Gym location evaluation is deferred to a follow-up geofence track.',
  );
});

// POST /gyms/events
router.post(
  '/events',
  isAuthenticated,
  validateBody(gymEventSchema),
  async (req, res) => {
    try {
      const userId = new Types.ObjectId(getUserId(req));
      const { gymId, eventType, occurredAt, latitude, longitude, source } =
        req.body as z.infer<typeof gymEventSchema>;

      if (!Types.ObjectId.isValid(gymId)) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'gymId must be a valid ObjectId');
        return;
      }

      const gym = await Gym.findOne({
        _id: new Types.ObjectId(gymId),
        userId,
      });

      if (!gym) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Gym not found');
        return;
      }

      const timestamp = occurredAt ?? new Date();
      const location =
        latitude !== undefined && longitude !== undefined
          ? { latitude, longitude }
          : null;
      const sessionEventType = eventType === 'entry' ? 'gym_entry' : 'gym_exit';

      await EventLog.create({
        userId,
        eventType: sessionEventType,
        source,
        timestamp,
        metadata: {
          gymId: String(gym._id),
          gymName: gym.name,
          latitude: location?.latitude ?? null,
          longitude: location?.longitude ?? null,
        },
      });

      let session = await GymSession.findOne({
        userId,
        gymId: gym._id,
        endedAt: null,
      }).sort({ startedAt: -1 });

      if (eventType === 'entry') {
        if (!session) {
          session = await GymSession.create({
            userId,
            gymId: gym._id,
            gymName: gym.name,
            startedAt: timestamp,
            source: 'geofence',
            events: [],
          });
        }
      }

      if (session) {
        session.events.push({
          type: sessionEventType,
          timestamp,
          metadata: {
            latitude: location?.latitude ?? null,
            longitude: location?.longitude ?? null,
            radiusMeters: gym.radiusMeters,
          },
        });

        if (eventType === 'exit' && !session.endedAt) {
          session.endedAt = timestamp;
          session.durationMinutes = Math.max(
            0,
            Math.round((timestamp.getTime() - session.startedAt.getTime()) / 60_000),
          );
        }

        await session.save();
      }

      successResponse(res, {
        gymId: String(gym._id),
        eventType,
        occurredAt: timestamp,
        sessionId: session ? String(session._id) : null,
      });
    } catch (err) {
      handleGymError(res, err, 'Failed to ingest gym event');
    }
  },
);

// GET /gyms/nearby
router.get('/nearby', isAuthenticated, (_req, res) => {
  errorResponse(
    res,
    StatusCodes.NOT_IMPLEMENTED,
    'Nearby gym discovery is deferred to a follow-up geofence track.',
  );
});

// GET /gyms/:id
router.get('/:id', isAuthenticated, async (req, res) => {
  try {
    const gym = await gymService.getGym(getUserId(req), getRouteParam(req, 'id'));
    successResponse(res, gym);
  } catch (err) {
    handleGymError(res, err, 'Failed to load gym');
  }
});

// PATCH /gyms/:id
router.patch(
  '/:id',
  isAuthenticated,
  validateBody(updateGymSchema),
  async (req, res) => {
    try {
      const gym = await gymService.updateGym(
        getUserId(req),
        getRouteParam(req, 'id'),
        req.body as z.infer<typeof updateGymSchema>,
      );
      successResponse(res, gym);
    } catch (err) {
      handleGymError(res, err, 'Failed to update gym');
    }
  },
);

// PATCH /gyms/:id/default
router.patch('/:id/default', isAuthenticated, async (req, res) => {
  try {
    await gymService.setDefaultGym(getUserId(req), getRouteParam(req, 'id'));
    successResponse(res, {});
  } catch (err) {
    handleGymError(res, err, 'Failed to set default gym');
  }
});

// DELETE /gyms/:id
router.delete('/:id', isAuthenticated, async (req, res) => {
  try {
    await gymService.deleteGym(getUserId(req), getRouteParam(req, 'id'));
    successResponse(res, {});
  } catch (err) {
    handleGymError(res, err, 'Failed to delete gym');
  }
});

// POST /gyms/:id/check-in
router.post('/:id/check-in', isAuthenticated, (_req, res) => {
  errorResponse(
    res,
    StatusCodes.NOT_IMPLEMENTED,
    'Gym check-in events are deferred to a follow-up geofence track.',
  );
});

export default router;
