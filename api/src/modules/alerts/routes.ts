import { Router, type Request } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { Alert } from '../../models/Alert.js';
import { Device } from '../../models/Device.js';
import { errorResponse, successResponse } from '../../utils/response.js';

const router = Router();

const deviceDisconnectedSchema = z.object({
  deviceId: z.string().trim().min(1),
  deviceName: z.string().trim().min(1).max(160),
  lastSeenAt: z.coerce.date(),
  latitude: z.coerce.number().finite().optional().nullable(),
  longitude: z.coerce.number().finite().optional().nullable(),
});

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function getRouteParam(req: Request, key: string): string {
  const value = req.params[key];
  return Array.isArray(value) ? value[0] : value;
}

function resolveAlertType(type: string): string {
  if (type === 'disconnect_warning') {
    return 'device_disconnected';
  }

  return type;
}

function buildAlertMessage(alert: {
  type: string;
  severity: string;
  metadata?: Record<string, unknown> | null;
}): string {
  const deviceName =
    typeof alert.metadata?.deviceName === 'string' ? alert.metadata.deviceName : null;
  const explicitMessage =
    typeof alert.metadata?.message === 'string' ? alert.metadata.message : null;

  if (explicitMessage) {
    return explicitMessage;
  }

  switch (alert.type) {
    case 'device_disconnected':
    case 'disconnect_warning':
      return `${deviceName ?? 'A monitored device'} disconnected unexpectedly.`;
    case 'panic_alarm':
      return `${deviceName ?? 'A monitored device'} triggered a panic alarm.`;
    case 'reconnect_found':
      return `${deviceName ?? 'Your device'} reconnected.`;
    case 'gym_entry_activate':
      return 'Gym monitoring activated from a geofence entry.';
    case 'gym_exit_deactivate':
      return 'Gym monitoring deactivated after leaving the geofence.';
    default:
      return `Alert received (${alert.type}, ${alert.severity}).`;
  }
}

function buildAlertResponse(alert: {
  _id: { toString(): string };
  type: string;
  severity: string;
  deviceId?: string | null;
  status: string;
  acknowledgedAt?: Date | null;
  metadata?: Record<string, unknown> | null;
  createdAt: Date;
}) {
  return {
    _id: alert._id.toString(),
    type: resolveAlertType(alert.type),
    severity: alert.severity,
    message: buildAlertMessage(alert),
    deviceId: alert.deviceId ?? null,
    deviceName:
      typeof alert.metadata?.deviceName === 'string' ? alert.metadata.deviceName : null,
    latitude:
      typeof alert.metadata?.latitude === 'number' ? alert.metadata.latitude : null,
    longitude:
      typeof alert.metadata?.longitude === 'number' ? alert.metadata.longitude : null,
    acknowledged: alert.status !== 'open',
    acknowledgedAt: alert.acknowledgedAt ?? null,
    createdAt: alert.createdAt,
  };
}

// GET /alerts
router.get('/', isAuthenticated, async (req, res) => {
  try {
    const alerts = await Alert.find({ userId: new Types.ObjectId(getUserId(req)) })
      .sort({ createdAt: -1 })
      .limit(100)
      .lean();

    successResponse(res, alerts.map((alert) => buildAlertResponse(alert)));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load alerts',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /alerts/device-disconnected
router.post('/device-disconnected', isAuthenticated, async (req, res) => {
  try {
    const parsed = deviceDisconnectedSchema.safeParse(req.body);
    if (!parsed.success) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'Validation failed',
        parsed.error.flatten().fieldErrors,
      );
      return;
    }

    const userId = new Types.ObjectId(getUserId(req));
    const { deviceId, deviceName, lastSeenAt, latitude, longitude } = parsed.data;
    const normalizedDeviceId = deviceId.trim();

    const existingOpenAlert = await Alert.findOne({
      userId,
      type: { $in: ['disconnect_warning', 'device_disconnected'] },
      deviceId: normalizedDeviceId,
      status: 'open',
    });

    if (existingOpenAlert) {
      existingOpenAlert.triggeredAt = lastSeenAt;
      existingOpenAlert.metadata = {
        ...(existingOpenAlert.metadata ?? {}),
        deviceName,
        lastSeenAt: lastSeenAt.toISOString(),
        latitude: latitude ?? null,
        longitude: longitude ?? null,
      };
      await existingOpenAlert.save();
      successResponse(res, {}, StatusCodes.CREATED);
      return;
    }

    if (Types.ObjectId.isValid(normalizedDeviceId)) {
      const device = await Device.findOne({
        _id: new Types.ObjectId(normalizedDeviceId),
        userId,
      });

      if (device) {
        device.status = 'disconnected';
        device.lastSeenAt = lastSeenAt;
        if (latitude !== undefined && latitude !== null && longitude !== undefined && longitude !== null) {
          device.lastSeenLocation = {
            type: 'Point',
            coordinates: [longitude, latitude],
          };
        }
        await device.save();
      }
    }

    await Alert.create({
      userId,
      deviceId: normalizedDeviceId,
      type: 'device_disconnected',
      severity: 'high',
      status: 'open',
      triggeredAt: lastSeenAt,
      metadata: {
        deviceName,
        lastSeenAt: lastSeenAt.toISOString(),
        latitude: latitude ?? null,
        longitude: longitude ?? null,
        message: `${deviceName} disconnected unexpectedly.`,
      },
    });

    successResponse(res, {}, StatusCodes.CREATED);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to create disconnect alert',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /alerts/:id/acknowledge
router.post('/:id/acknowledge', isAuthenticated, async (req, res) => {
  try {
    const alertId = getRouteParam(req, 'id');
    if (!Types.ObjectId.isValid(alertId)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid alert id');
      return;
    }

    const alert = await Alert.findOne({
      _id: new Types.ObjectId(alertId),
      userId: new Types.ObjectId(getUserId(req)),
    });

    if (!alert) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Alert not found');
      return;
    }

    if (alert.status === 'open') {
      alert.status = 'acknowledged';
      alert.acknowledgedAt = new Date();
      await alert.save();
    }

    successResponse(res, {});
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to acknowledge alert',
      err instanceof Error ? err.message : String(err),
    );
  }
});

export default router;
