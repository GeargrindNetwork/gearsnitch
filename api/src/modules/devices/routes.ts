import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import logger from '../../utils/logger.js';
import { errorResponse, successResponse } from '../../utils/response.js';
import { DeviceService, DeviceServiceError } from './deviceService.js';
import { DeviceShare } from '../../models/DeviceShare.js';
import { Device } from '../../models/Device.js';
import { User } from '../../models/User.js';

const router = Router();
const deviceService = new DeviceService();

const createDeviceSchema = z.object({
  name: z.string().trim().min(1).max(120),
  nickname: z.preprocess((value) => {
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : null;
    }

    return value;
  }, z.string().min(1).max(120).nullable()).optional(),
  bluetoothIdentifier: z.string().trim().min(1).max(255),
  type: z.enum(['earbuds', 'tracker', 'belt', 'bag', 'watch', 'other']),
  isFavorite: z.boolean().optional(),
});

const updateDeviceSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  nickname: z.preprocess((value) => {
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : null;
    }

    return value;
  }, z.string().min(1).max(120).nullable()).optional(),
  type: z.enum(['earbuds', 'tracker', 'belt', 'bag', 'watch', 'other']).optional(),
  isFavorite: z.boolean().optional(),
}).refine((body) =>
  body.name !== undefined
  || body.nickname !== undefined
  || body.type !== undefined
  || body.isFavorite !== undefined, {
  message: 'At least one field must be provided',
});

const updateStatusSchema = z.object({
  status: z.enum([
    'registered',
    'active',
    'inactive',
    'connected',
    'monitoring',
    'disconnected',
    'lost',
    'reconnected',
  ]),
  lastSeenLocation: z
    .object({
      type: z.literal('Point'),
      coordinates: z.tuple([z.number().finite(), z.number().finite()]),
    })
    .optional(),
  lastSignalStrength: z.number().int().min(-150).max(0).optional(),
  recordedAt: z.coerce.date().optional(),
});

const recordDeviceEventSchema = z.object({
  action: z.enum(['connect', 'disconnect']),
  occurredAt: z.coerce.date().optional(),
  location: z
    .object({
      type: z.literal('Point'),
      coordinates: z.tuple([z.number().finite(), z.number().finite()]),
    })
    .optional(),
  signalStrength: z.number().int().min(-150).max(0).optional(),
  source: z.enum(['ios', 'web', 'system']).optional(),
  metadata: z.record(z.unknown()).nullable().optional(),
});

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function getRouteParam(req: Request, key: string): string {
  const value = req.params[key];
  return Array.isArray(value) ? value[0] : value;
}

function handleDeviceError(
  req: Request,
  res: Response,
  err: unknown,
  fallbackMessage: string,
  context?: Record<string, unknown>,
): void {
  if (err instanceof DeviceServiceError) {
    errorResponse(res, err.statusCode, err.message);
    return;
  }

  logger.error('Unexpected device route error', {
    correlationId: req.requestId,
    method: req.method,
    url: req.originalUrl,
    userId: req.user ? (req.user as JwtPayload).sub : undefined,
    ...context,
    error:
      err instanceof Error
        ? {
            name: err.name,
            message: err.message,
            stack: err.stack,
          }
        : { message: String(err) },
  });

  errorResponse(
    res,
    StatusCodes.INTERNAL_SERVER_ERROR,
    fallbackMessage,
    err instanceof Error ? err.message : String(err),
  );
}

// GET /devices
router.get('/', isAuthenticated, async (req, res) => {
  try {
    const devices = await deviceService.listDevices(getUserId(req));
    successResponse(res, devices);
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to list devices', {
      operation: 'listDevices',
    });
  }
});

// POST /devices
router.post(
  '/',
  isAuthenticated,
  validateBody(createDeviceSchema),
  async (req, res) => {
    try {
      const device = await deviceService.createDevice(
        getUserId(req),
        req.body as z.infer<typeof createDeviceSchema>,
      );
      successResponse(res, device, StatusCodes.CREATED);
    } catch (err) {
      const body = req.body as Partial<z.infer<typeof createDeviceSchema>>;
      handleDeviceError(req, res, err, 'Failed to register device', {
        operation: 'createDevice',
        requestBody: {
          name: body.name,
          nickname: body.nickname,
          type: body.type,
          bluetoothIdentifier: body.bluetoothIdentifier,
          isFavorite: body.isFavorite,
        },
      });
    }
  },
);

// GET /devices/locations
router.get('/locations', isAuthenticated, async (req, res) => {
  try {
    const locations = await deviceService.listLocations(getUserId(req));
    successResponse(res, locations);
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to list device locations', {
      operation: 'listDeviceLocations',
    });
  }
});

// GET /devices/:id
router.get('/:id', isAuthenticated, async (req, res) => {
  try {
    const device = await deviceService.getDevice(getUserId(req), getRouteParam(req, 'id'));
    successResponse(res, device);
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to load device', {
      operation: 'getDevice',
      deviceId: getRouteParam(req, 'id'),
    });
  }
});

// GET /devices/:id/events
router.get('/:id/events', isAuthenticated, async (req, res) => {
  try {
    const events = await deviceService.listEvents(getUserId(req), getRouteParam(req, 'id'));
    successResponse(res, events);
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to load device event history', {
      operation: 'listDeviceEvents',
      deviceId: getRouteParam(req, 'id'),
    });
  }
});

// PATCH /devices/:id
router.patch(
  '/:id',
  isAuthenticated,
  validateBody(updateDeviceSchema),
  async (req, res) => {
    try {
      const device = await deviceService.updateDevice(
        getUserId(req),
        getRouteParam(req, 'id'),
        req.body as z.infer<typeof updateDeviceSchema>,
      );
      successResponse(res, device);
    } catch (err) {
      handleDeviceError(req, res, err, 'Failed to update device', {
        operation: 'updateDevice',
        deviceId: getRouteParam(req, 'id'),
      });
    }
  },
);

// PATCH /devices/:id/status
router.patch(
  '/:id/status',
  isAuthenticated,
  validateBody(updateStatusSchema),
  async (req, res) => {
    try {
      await deviceService.updateStatus(
        getUserId(req),
        getRouteParam(req, 'id'),
        req.body as z.infer<typeof updateStatusSchema>,
      );
      successResponse(res, {});
    } catch (err) {
      handleDeviceError(req, res, err, 'Failed to update device status', {
        operation: 'updateDeviceStatus',
        deviceId: getRouteParam(req, 'id'),
      });
    }
  },
);

// POST /devices/:id/events
router.post(
  '/:id/events',
  isAuthenticated,
  validateBody(recordDeviceEventSchema),
  async (req, res) => {
    try {
      const event = await deviceService.recordEvent(
        getUserId(req),
        getRouteParam(req, 'id'),
        req.body as z.infer<typeof recordDeviceEventSchema>,
      );
      successResponse(res, event, StatusCodes.CREATED);
    } catch (err) {
      handleDeviceError(req, res, err, 'Failed to record device event', {
        operation: 'recordDeviceEvent',
        deviceId: getRouteParam(req, 'id'),
      });
    }
  },
);

// DELETE /devices/:id
router.delete('/:id', isAuthenticated, async (req, res) => {
  try {
    await deviceService.deleteDevice(getUserId(req), getRouteParam(req, 'id'));
    successResponse(res, {});
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to remove device', {
      operation: 'deleteDevice',
      deviceId: getRouteParam(req, 'id'),
    });
  }
});

// ─── Device Sharing ───────────────────────────────────────────────────────

const shareDeviceSchema = z.object({
  email: z.string().email().min(1),
  canReceiveAlerts: z.boolean().optional().default(true),
});

// GET /devices/:id/shares
router.get('/:id/shares', isAuthenticated, async (req, res) => {
  try {
    const userId = getUserId(req);
    const deviceId = getRouteParam(req, 'id');

    // Verify ownership
    const device = await Device.findOne({ _id: deviceId, userId }).lean();
    if (!device) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Device not found');
      return;
    }

    const shares = await DeviceShare.find({ deviceId })
      .populate('sharedWithUserId', 'email displayName')
      .lean();

    const result = shares.map((s) => ({
      _id: String(s._id),
      email: (s.sharedWithUserId as any)?.email ?? 'Unknown',
      displayName: (s.sharedWithUserId as any)?.displayName ?? null,
      canReceiveAlerts: s.canReceiveAlerts,
      createdAt: s.createdAt?.toISOString(),
    }));

    successResponse(res, result);
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to list shares', { operation: 'listShares' });
  }
});

// POST /devices/:id/shares
router.post('/:id/shares', isAuthenticated, validateBody(shareDeviceSchema), async (req, res) => {
  try {
    const userId = getUserId(req);
    const deviceId = getRouteParam(req, 'id');
    const { email, canReceiveAlerts } = req.body as z.infer<typeof shareDeviceSchema>;

    // Verify ownership
    const device = await Device.findOne({ _id: deviceId, userId }).lean();
    if (!device) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Device not found');
      return;
    }

    // Find user by email
    const targetUser = await User.findOne({ email: email.toLowerCase().trim() }).lean();
    if (!targetUser) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'No user found with that email');
      return;
    }

    if (String(targetUser._id) === userId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Cannot share a device with yourself');
      return;
    }

    // Check for existing share
    const existing = await DeviceShare.findOne({
      deviceId,
      sharedWithUserId: targetUser._id,
    });
    if (existing) {
      errorResponse(res, StatusCodes.CONFLICT, 'Device is already shared with this user');
      return;
    }

    const share = await DeviceShare.create({
      deviceId,
      ownerUserId: userId,
      sharedWithUserId: targetUser._id,
      canReceiveAlerts,
    });

    successResponse(
      res,
      {
        _id: String(share._id),
        email,
        displayName: targetUser.displayName ?? null,
        canReceiveAlerts: share.canReceiveAlerts,
        createdAt: share.createdAt?.toISOString(),
      },
      StatusCodes.CREATED,
    );
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to share device', { operation: 'shareDevice' });
  }
});

// DELETE /devices/:id/shares/:shareId
router.delete('/:id/shares/:shareId', isAuthenticated, async (req, res) => {
  try {
    const userId = getUserId(req);
    const deviceId = getRouteParam(req, 'id');
    const shareId = req.params.shareId;

    // Verify ownership
    const device = await Device.findOne({ _id: deviceId, userId }).lean();
    if (!device) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Device not found');
      return;
    }

    const result = await DeviceShare.findOneAndDelete({
      _id: shareId,
      deviceId,
    });

    if (!result) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Share not found');
      return;
    }

    successResponse(res, { deleted: true });
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to remove share', { operation: 'removeShare' });
  }
});

export default router;
