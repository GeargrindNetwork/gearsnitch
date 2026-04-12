import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { errorResponse, successResponse } from '../../utils/response.js';
import { DeviceService, DeviceServiceError } from './deviceService.js';

const router = Router();
const deviceService = new DeviceService();

const createDeviceSchema = z.object({
  name: z.string().trim().min(1).max(120),
  bluetoothIdentifier: z.string().trim().min(1).max(255),
  type: z.enum(['earbuds', 'tracker', 'belt', 'bag', 'other']),
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
  type: z.enum(['earbuds', 'tracker', 'belt', 'bag', 'other']).optional(),
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
});

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function getRouteParam(req: Request, key: string): string {
  const value = req.params[key];
  return Array.isArray(value) ? value[0] : value;
}

function handleDeviceError(res: Response, err: unknown, fallbackMessage: string): void {
  if (err instanceof DeviceServiceError) {
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

// GET /devices
router.get('/', isAuthenticated, async (req, res) => {
  try {
    const devices = await deviceService.listDevices(getUserId(req));
    successResponse(res, devices);
  } catch (err) {
    handleDeviceError(res, err, 'Failed to list devices');
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
      handleDeviceError(res, err, 'Failed to register device');
    }
  },
);

// GET /devices/locations
router.get('/locations', isAuthenticated, async (req, res) => {
  try {
    const locations = await deviceService.listLocations(getUserId(req));
    successResponse(res, locations);
  } catch (err) {
    handleDeviceError(res, err, 'Failed to list device locations');
  }
});

// GET /devices/:id
router.get('/:id', isAuthenticated, async (req, res) => {
  try {
    const device = await deviceService.getDevice(getUserId(req), getRouteParam(req, 'id'));
    successResponse(res, device);
  } catch (err) {
    handleDeviceError(res, err, 'Failed to load device');
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
      handleDeviceError(res, err, 'Failed to update device');
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
        (req.body as z.infer<typeof updateStatusSchema>).status,
      );
      successResponse(res, {});
    } catch (err) {
      handleDeviceError(res, err, 'Failed to update device status');
    }
  },
);

// DELETE /devices/:id
router.delete('/:id', isAuthenticated, async (req, res) => {
  try {
    await deviceService.deleteDevice(getUserId(req), getRouteParam(req, 'id'));
    successResponse(res, {});
  } catch (err) {
    handleDeviceError(res, err, 'Failed to remove device');
  }
});

export default router;
