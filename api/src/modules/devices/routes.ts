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
import { RssiSample } from '../../models/RssiSample.js';
import { User } from '../../models/User.js';
import { enqueuePushNotification } from '../../services/pushNotificationQueue.js';

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

// Battery level endpoint (backlog item #17).
// Body carries the 0–100 percentage decoded by the iOS `BatteryLevelReader`
// from GATT char 0x2A19 (Battery Level) on service 0x180F.
const updateBatterySchema = z.object({
  level: z.number().int().min(0).max(100),
  readAt: z.coerce.date().optional(),
});

// RSSI history endpoints (backlog item #19).
//
// The iOS `RssiSampleBuffer` batches per-device RSSI readings while
// scanning/monitoring and POSTs them in chunks. Values are in dBm and
// should land in `[-120, 0]` (typical `[-100, -30]`). We cap the batch
// size at 100 so a chatty peripheral or buggy client can't overwhelm a
// single insertMany.
export const RSSI_BATCH_LIMIT = 100;

const rssiSampleSchema = z.object({
  rssi: z.number().finite().min(-120).max(0),
  sampledAt: z.coerce.date().optional(),
});

const ingestRssiSchema = z.object({
  samples: z
    .array(rssiSampleSchema)
    .min(1, 'At least one sample is required')
    .max(RSSI_BATCH_LIMIT, `Batch cannot exceed ${RSSI_BATCH_LIMIT} samples`),
});

const rssiHistoryQuerySchema = z.object({
  windowHours: z.coerce.number().int().min(1).max(168).default(24),
  buckets: z.coerce.number().int().min(1).max(240).default(60),
});

/** Single bucket in the RSSI history time-series response. */
export interface RssiHistoryBucket {
  ts: string;
  avgRssi: number;
  count: number;
}

/**
 * Pure bucketing helper. Exposed for unit tests.
 *
 * Partitions `samples` across `bucketCount` equal-width buckets that
 * span `[windowStart, windowEnd)`. Each bucket's `ts` is its start
 * timestamp; its `avgRssi` is the mean of samples whose `sampledAt`
 * falls inside it (buckets with no samples are omitted). The result is
 * returned in chronological order.
 */
export function bucketRssiSamples(
  samples: Array<{ rssi: number; sampledAt: Date }>,
  windowStart: Date,
  windowEnd: Date,
  bucketCount: number,
): RssiHistoryBucket[] {
  if (bucketCount <= 0) return [];

  const startMs = windowStart.getTime();
  const endMs = windowEnd.getTime();
  const totalMs = endMs - startMs;
  if (totalMs <= 0) return [];

  const bucketWidth = totalMs / bucketCount;
  const sums = new Array<number>(bucketCount).fill(0);
  const counts = new Array<number>(bucketCount).fill(0);

  for (const sample of samples) {
    const ts = sample.sampledAt.getTime();
    if (ts < startMs || ts >= endMs) continue;
    const idx = Math.min(
      bucketCount - 1,
      Math.floor((ts - startMs) / bucketWidth),
    );
    sums[idx] += sample.rssi;
    counts[idx] += 1;
  }

  const result: RssiHistoryBucket[] = [];
  for (let i = 0; i < bucketCount; i += 1) {
    const count = counts[i];
    if (count === 0) continue;
    const avg = sums[i] / count;
    const bucketStart = new Date(startMs + i * bucketWidth);
    result.push({
      ts: bucketStart.toISOString(),
      avgRssi: Math.round(avg * 10) / 10,
      count,
    });
  }
  return result;
}

/**
 * Computes the week-over-week average RSSI delta (this-week mean minus
 * prior-week mean, in dBm). Positive = signal got stronger. Returns
 * `null` if either window has no samples, so the UI can hide the
 * warning banner instead of flashing a misleading "+0 dBm" on a new
 * device. Exposed for unit tests.
 */
export function computeWeekOverWeekDelta(
  samples: Array<{ rssi: number; sampledAt: Date }>,
  now: Date,
): number | null {
  const dayMs = 24 * 60 * 60 * 1000;
  const thisWeekStart = now.getTime() - 7 * dayMs;
  const priorWeekStart = now.getTime() - 14 * dayMs;

  let thisSum = 0;
  let thisCount = 0;
  let priorSum = 0;
  let priorCount = 0;

  for (const s of samples) {
    const ts = s.sampledAt.getTime();
    if (ts >= thisWeekStart && ts <= now.getTime()) {
      thisSum += s.rssi;
      thisCount += 1;
    } else if (ts >= priorWeekStart && ts < thisWeekStart) {
      priorSum += s.rssi;
      priorCount += 1;
    }
  }

  if (thisCount === 0 || priorCount === 0) return null;
  const thisAvg = thisSum / thisCount;
  const priorAvg = priorSum / priorCount;
  return Math.round((thisAvg - priorAvg) * 10) / 10;
}

// Server-side 12h cooldown between low-battery pushes per device. Tied to
// `device.lastLowBatteryNotifiedAt` so a device that flaps below 20% every
// minute doesn't spam the user. Threshold is 20% per PRD.
export const LOW_BATTERY_THRESHOLD = 20;
export const LOW_BATTERY_COOLDOWN_MS = 12 * 60 * 60 * 1000;

export function shouldSendLowBatteryPush(
  level: number,
  lastNotifiedAt: Date | null | undefined,
  now: Date = new Date(),
): boolean {
  if (level >= LOW_BATTERY_THRESHOLD) return false;
  if (!lastNotifiedAt) return true;
  return now.getTime() - new Date(lastNotifiedAt).getTime() >= LOW_BATTERY_COOLDOWN_MS;
}

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

// PATCH /devices/:id/battery — iOS `BatteryLevelReader` POSTs the decoded
// BLE Battery Level characteristic (0x2A19) here. We persist the reading
// and enqueue a low-battery push (respecting a 12h per-device cooldown)
// when the level crosses under 20%.
router.patch(
  '/:id/battery',
  isAuthenticated,
  validateBody(updateBatterySchema),
  async (req, res) => {
    try {
      const userId = getUserId(req);
      const deviceId = getRouteParam(req, 'id');
      const { level, readAt } = req.body as z.infer<typeof updateBatterySchema>;
      const now = readAt ?? new Date();

      const device = await Device.findOne({ _id: deviceId, userId });
      if (!device) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Device not found');
        return;
      }

      device.lastBatteryLevel = level;
      device.lastBatteryReadAt = now;

      let lowBatteryNotified = false;
      if (shouldSendLowBatteryPush(level, device.lastLowBatteryNotifiedAt ?? null, now)) {
        try {
          await enqueuePushNotification({
            userId: String(userId),
            type: 'device_low_battery',
            title: `Low battery on ${device.name}`,
            body: `Battery at ${level}%. Tap to dismiss.`,
            data: {
              type: 'device_low_battery',
              deviceId: String(device._id),
              level,
            },
            // Scoped to 12h window so retries/replays don't refire within
            // the cooldown even if the client re-POSTs the same reading.
            dedupeKey: `device-low-battery:${String(device._id)}:${Math.floor(
              now.getTime() / LOW_BATTERY_COOLDOWN_MS,
            )}`,
          });
          device.lastLowBatteryNotifiedAt = now;
          lowBatteryNotified = true;
        } catch (pushErr) {
          logger.warn('Failed to enqueue low-battery push', {
            deviceId,
            userId,
            error: pushErr instanceof Error ? pushErr.message : String(pushErr),
          });
        }
      }

      await device.save();

      successResponse(res, {
        _id: String(device._id),
        lastBatteryLevel: device.lastBatteryLevel ?? null,
        lastBatteryReadAt: device.lastBatteryReadAt ?? null,
        lowBatteryNotified,
      });
    } catch (err) {
      handleDeviceError(req, res, err, 'Failed to update device battery level', {
        operation: 'updateDeviceBattery',
        deviceId: getRouteParam(req, 'id'),
      });
    }
  },
);

// POST /devices/:id/rssi — iOS `BLEManager` POSTs a batch of RSSI
// samples here (backlog item #19). Samples are bulk-inserted into the
// `RssiSample` collection which is TTL-bounded to 7 days.
router.post(
  '/:id/rssi',
  isAuthenticated,
  validateBody(ingestRssiSchema),
  async (req, res) => {
    try {
      const userId = getUserId(req);
      const deviceId = getRouteParam(req, 'id');
      const { samples } = req.body as z.infer<typeof ingestRssiSchema>;

      const device = await Device.findOne({ _id: deviceId, userId }).lean();
      if (!device) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Device not found');
        return;
      }

      const now = new Date();
      const docs = samples.map((s) => ({
        userId: device.userId,
        deviceId: device._id,
        rssi: s.rssi,
        sampledAt: s.sampledAt ?? now,
      }));

      const inserted = await RssiSample.insertMany(docs, { ordered: false });

      // Bonus: keep `lastSignalStrength` fresh using the latest sample
      // in the batch so existing UI that reads it (Bluetooth info card
      // on DeviceDetailView) doesn't go stale.
      let latest = samples[0];
      for (const s of samples) {
        const sampledAt = s.sampledAt ?? now;
        const latestAt = latest.sampledAt ?? now;
        if (sampledAt >= latestAt) latest = s;
      }
      await Device.updateOne(
        { _id: deviceId, userId },
        {
          $set: {
            lastSignalStrength: Math.round(latest.rssi),
            lastSeenAt: latest.sampledAt ?? now,
          },
        },
      );

      successResponse(res, {
        inserted: inserted.length,
      }, StatusCodes.CREATED);
    } catch (err) {
      handleDeviceError(req, res, err, 'Failed to ingest RSSI samples', {
        operation: 'ingestRssiSamples',
        deviceId: getRouteParam(req, 'id'),
      });
    }
  },
);

// GET /devices/:id/rssi/history — returns bucketed RSSI time-series
// for `DeviceDetailView`'s Signal History chart (backlog item #19).
router.get('/:id/rssi/history', isAuthenticated, async (req, res) => {
  try {
    const userId = getUserId(req);
    const deviceId = getRouteParam(req, 'id');

    const parsed = rssiHistoryQuerySchema.safeParse(req.query);
    if (!parsed.success) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'Invalid query parameters',
        parsed.error.flatten(),
      );
      return;
    }
    const { windowHours, buckets } = parsed.data;

    const device = await Device.findOne({ _id: deviceId, userId }).lean();
    if (!device) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Device not found');
      return;
    }

    const now = new Date();
    const windowStart = new Date(now.getTime() - windowHours * 60 * 60 * 1000);
    const wowStart = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000);

    // Pull everything we need for both the chart window and the WoW
    // delta in a single query so we don't double-hit the index.
    const rangeStart = wowStart < windowStart ? wowStart : windowStart;
    const samples = await RssiSample.find(
      {
        deviceId: device._id,
        sampledAt: { $gte: rangeStart, $lte: now },
      },
      { rssi: 1, sampledAt: 1, _id: 0 },
    )
      .sort({ sampledAt: 1 })
      .lean();

    const windowSamples = samples.filter(
      (s) => s.sampledAt >= windowStart && s.sampledAt <= now,
    );
    const bucketsOut = bucketRssiSamples(windowSamples, windowStart, now, buckets);

    // Lifetime average across everything we still have (bounded to 7
    // days by the TTL index, which is plenty for a "recent baseline").
    const lifetimeAvg = samples.length
      ? Math.round((samples.reduce((acc, s) => acc + s.rssi, 0) / samples.length) * 10) / 10
      : null;

    const weekOverWeekDelta = computeWeekOverWeekDelta(samples, now);

    successResponse(res, {
      deviceId: String(device._id),
      windowHours,
      buckets: bucketsOut,
      lifetimeAvg,
      weekOverWeekDelta,
    });
  } catch (err) {
    handleDeviceError(req, res, err, 'Failed to load RSSI history', {
      operation: 'getRssiHistory',
      deviceId: getRouteParam(req, 'id'),
    });
  }
});

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
