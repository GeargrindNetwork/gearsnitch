import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import logger from '../../utils/logger.js';
import { errorResponse, successResponse } from '../../utils/response.js';
import {
  GearComponent,
  GEAR_KINDS,
  GEAR_STATUSES,
  GEAR_UNITS,
  type IGearComponent,
} from '../../models/GearComponent.js';
import { EventLog } from '../../models/EventLog.js';
import { User } from '../../models/User.js';
import { enqueuePushNotification } from '../../services/pushNotificationQueue.js';
import { resolveDefaultGear } from './autoAttach.js';

/**
 * Gear retirement + component mileage routes (backlog item #4).
 *
 * Lets a user track consumable gear (shoes, chains, tires, ...) against a
 * `lifeLimit` in `unit`s and emits APNs push notifications when the user
 * crosses the warning threshold or hits the retirement limit. Pushes are
 * delivered through the worker `push-notifications` queue (see PR #48 and
 * `services/pushNotificationQueue.ts`).
 */

const router = Router();

const createGearSchema = z.object({
  name: z.string().trim().min(1).max(200),
  kind: z.enum(GEAR_KINDS),
  unit: z.enum(GEAR_UNITS),
  lifeLimit: z.number().finite().positive(),
  warningThreshold: z.number().finite().min(0).max(1).optional().default(0.85),
  currentValue: z.number().finite().min(0).optional().default(0),
  deviceId: z.string().trim().min(1).optional(),
});

const updateGearSchema = z
  .object({
    name: z.string().trim().min(1).max(200).optional(),
    kind: z.enum(GEAR_KINDS).optional(),
    unit: z.enum(GEAR_UNITS).optional(),
    lifeLimit: z.number().finite().positive().optional(),
    warningThreshold: z.number().finite().min(0).max(1).optional(),
    currentValue: z.number().finite().min(0).optional(),
    status: z.enum(GEAR_STATUSES).optional(),
    deviceId: z.string().trim().min(1).nullable().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, {
    message: 'At least one field must be provided',
  });

const logUsageSchema = z.object({
  amount: z.number().finite().positive(),
});

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function serializeComponent(doc: IGearComponent | Record<string, any>) {
  const plain = typeof (doc as IGearComponent).toObject === 'function'
    ? (doc as IGearComponent).toObject()
    : (doc as Record<string, any>);

  const lifeLimit = Number(plain.lifeLimit ?? 0);
  const currentValue = Number(plain.currentValue ?? 0);
  const warningThreshold = Number(plain.warningThreshold ?? 0.85);
  const usagePct = lifeLimit > 0 ? currentValue / lifeLimit : 0;

  return {
    _id: String(plain._id),
    userId: plain.userId ? String(plain.userId) : null,
    deviceId: plain.deviceId ? String(plain.deviceId) : null,
    name: plain.name,
    kind: plain.kind,
    unit: plain.unit,
    lifeLimit,
    warningThreshold,
    currentValue,
    usagePct,
    status: plain.status,
    retiredAt: plain.retiredAt ?? null,
    createdAt: plain.createdAt ?? null,
    updatedAt: plain.updatedAt ?? null,
  };
}

// Crossing detection helper exported for test reuse and worker introspection.
export function evaluateThresholdCrossings(
  previousValue: number,
  newValue: number,
  lifeLimit: number,
  warningThreshold: number,
): { crossedWarning: boolean; crossedRetirement: boolean } {
  const warningAt = lifeLimit * warningThreshold;
  const crossedWarning = previousValue < warningAt && newValue >= warningAt;
  const crossedRetirement = previousValue < lifeLimit && newValue >= lifeLimit;
  return { crossedWarning, crossedRetirement };
}

// Backlog item #9 — default gear per HKWorkoutActivityType.
//
// GET /gear/default-for-activity?activityType=<string>
//   → { gear: IGearComponent | null }
// PUT /gear/default-for-activity
//   body: { activityType: string, gearId: string | null }
//   → sets user.preferences.defaultGearByActivity[activityType] = gearId
//     (or unsets it when gearId === null). Ownership-checked.
const activityTypeSchema = z.string().trim().regex(/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/);
const putDefaultGearSchema = z.object({
  activityType: activityTypeSchema,
  gearId: z.union([z.string().regex(/^[a-fA-F0-9]{24}$/), z.null()]),
});

router.get('/default-for-activity', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId(getUserId(req));
    const activityType = typeof req.query.activityType === 'string'
      ? req.query.activityType
      : '';
    const parsed = activityTypeSchema.safeParse(activityType);
    if (!parsed.success) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid activityType');
      return;
    }

    const gear = await resolveDefaultGear(userId, parsed.data);
    successResponse(res, {
      gear: gear ? serializeComponent(gear) : null,
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to resolve default gear',
      err instanceof Error ? err.message : String(err),
    );
  }
});

router.put(
  '/default-for-activity',
  isAuthenticated,
  validateBody(putDefaultGearSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId(getUserId(req));
      const { activityType, gearId } = req.body as z.infer<typeof putDefaultGearSchema>;

      // Validate gear ownership before persisting — a malicious client must
      // not be able to point their default map at another user's gear id.
      if (gearId !== null) {
        const gear = await GearComponent.findOne({
          _id: new Types.ObjectId(gearId),
          userId,
        }).select('_id').lean();
        if (!gear) {
          errorResponse(res, StatusCodes.NOT_FOUND, 'Gear not found for this user');
          return;
        }
      }

      const user = await User.findById(userId);
      if (!user) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
        return;
      }

      const map = (user.preferences?.defaultGearByActivity ?? {}) as Record<string, unknown>;
      if (gearId === null) {
        delete map[activityType];
      } else {
        map[activityType] = new Types.ObjectId(gearId);
      }

      if (!user.preferences) {
        // Should never happen — preferences has defaults — but guard anyway.
        (user as any).preferences = { defaultGearByActivity: map } as any;
      } else {
        user.preferences.defaultGearByActivity = map as Record<string, Types.ObjectId | null>;
      }
      // Mongoose does not dirty-track Mixed subpaths automatically.
      user.markModified('preferences.defaultGearByActivity');
      await user.save();

      successResponse(res, {
        activityType,
        gearId: gearId,
        defaultGearByActivity: map,
      });
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update default gear',
        err instanceof Error ? err.message : String(err),
      );
    }
  },
);

// POST /gear — create
router.post(
  '/',
  isAuthenticated,
  validateBody(createGearSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId(getUserId(req));
      const body = req.body as z.infer<typeof createGearSchema>;

      const component = await GearComponent.create({
        userId,
        deviceId: body.deviceId ? new Types.ObjectId(body.deviceId) : null,
        name: body.name,
        kind: body.kind,
        unit: body.unit,
        lifeLimit: body.lifeLimit,
        warningThreshold: body.warningThreshold,
        currentValue: body.currentValue,
        status: 'active',
      });

      successResponse(res, serializeComponent(component), StatusCodes.CREATED);
    } catch (err) {
      logger.error('Failed to create gear component', {
        correlationId: req.requestId,
        error: err instanceof Error ? err.message : String(err),
      });
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to create gear component',
        err instanceof Error ? err.message : String(err),
      );
    }
  },
);

// GET /gear — list user's gear
router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId(getUserId(req));
    const status = typeof req.query.status === 'string' ? req.query.status : undefined;
    const filter: Record<string, unknown> = { userId };
    if (status && (GEAR_STATUSES as readonly string[]).includes(status)) {
      filter.status = status;
    }

    const components = await GearComponent.find(filter)
      .sort({ status: 1, updatedAt: -1 })
      .lean();

    successResponse(res, components.map(serializeComponent));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list gear',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// PATCH /gear/:id — update
router.patch(
  '/:id',
  isAuthenticated,
  validateBody(updateGearSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId(getUserId(req));
      const id = req.params.id as string;
      if (!Types.ObjectId.isValid(id)) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid gear id');
        return;
      }

      const body = req.body as z.infer<typeof updateGearSchema>;
      const update: Record<string, unknown> = { ...body };
      if (body.deviceId === null) {
        update.deviceId = null;
      } else if (typeof body.deviceId === 'string') {
        update.deviceId = new Types.ObjectId(body.deviceId);
      }

      const component = await GearComponent.findOneAndUpdate(
        { _id: new Types.ObjectId(id), userId },
        { $set: update },
        { new: true },
      );

      if (!component) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Gear component not found');
        return;
      }

      successResponse(res, serializeComponent(component));
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update gear',
        err instanceof Error ? err.message : String(err),
      );
    }
  },
);

// POST /gear/:id/log-usage — atomic mileage increment + threshold detection
router.post(
  '/:id/log-usage',
  isAuthenticated,
  validateBody(logUsageSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId(getUserId(req));
      const id = req.params.id as string;
      if (!Types.ObjectId.isValid(id)) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid gear id');
        return;
      }

      const { amount } = req.body as z.infer<typeof logUsageSchema>;

      // Read previous state, then atomically increment. We want the "previous"
      // and "next" snapshots so we can fire pushes only on the *crossing*
      // edge — not every time the user logs usage past the threshold.
      const before = await GearComponent.findOne({
        _id: new Types.ObjectId(id),
        userId,
      });

      if (!before) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Gear component not found');
        return;
      }

      if (before.status !== 'active') {
        errorResponse(
          res,
          StatusCodes.CONFLICT,
          `Cannot log usage on ${before.status} gear`,
        );
        return;
      }

      const previousValue = before.currentValue;
      const after = await GearComponent.findOneAndUpdate(
        { _id: before._id, userId },
        { $inc: { currentValue: amount } },
        { new: true },
      );

      if (!after) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Gear component not found');
        return;
      }

      const { crossedWarning, crossedRetirement } = evaluateThresholdCrossings(
        previousValue,
        after.currentValue,
        after.lifeLimit,
        after.warningThreshold,
      );

      // Auto-retire when the user reaches the limit. We pick the
      // auto-retirement path (rather than waiting for an explicit user
      // press) so the gear stops accumulating phantom miles in the case
      // where the user ignores the push.
      let finalComponent = after;
      if (crossedRetirement) {
        finalComponent = await GearComponent.findOneAndUpdate(
          { _id: after._id, userId },
          { $set: { status: 'retired', retiredAt: new Date() } },
          { new: true },
        ) ?? after;
      }

      // Fire pushes + event logs. Best-effort — failure to enqueue must not
      // fail the user's mileage log.
      try {
        if (crossedWarning) {
          const pct = Math.round((finalComponent.currentValue / finalComponent.lifeLimit) * 100);
          await enqueuePushNotification({
            userId: String(userId),
            type: 'gear_warning',
            title: 'Gear approaching retirement',
            body: `${finalComponent.name} is at ${formatValue(finalComponent.currentValue)}/${formatValue(finalComponent.lifeLimit)} ${finalComponent.unit} (${pct}%)`,
            data: {
              type: 'gear_warning',
              componentId: String(finalComponent._id),
            },
            dedupeKey: `gear-warning:${String(finalComponent._id)}`,
          });
          await EventLog.create({
            userId,
            eventType: 'GearWarningCrossed',
            metadata: {
              componentId: String(finalComponent._id),
              currentValue: finalComponent.currentValue,
              lifeLimit: finalComponent.lifeLimit,
            },
            source: 'system',
          });
        }

        if (crossedRetirement) {
          await enqueuePushNotification({
            userId: String(userId),
            type: 'gear_retirement',
            title: 'Gear ready to retire',
            body: `${finalComponent.name} has reached ${formatValue(finalComponent.currentValue)}/${formatValue(finalComponent.lifeLimit)} ${finalComponent.unit} — time to replace.`,
            data: {
              type: 'gear_retirement',
              componentId: String(finalComponent._id),
            },
            dedupeKey: `gear-retirement:${String(finalComponent._id)}`,
          });
          await EventLog.create({
            userId,
            eventType: 'GearRetirementCrossed',
            metadata: {
              componentId: String(finalComponent._id),
              currentValue: finalComponent.currentValue,
              lifeLimit: finalComponent.lifeLimit,
            },
            source: 'system',
          });
          await EventLog.create({
            userId,
            eventType: 'GearRetired',
            metadata: {
              componentId: String(finalComponent._id),
              autoRetired: true,
            },
            source: 'system',
          });
        }
      } catch (notifyErr) {
        logger.warn('Gear threshold push enqueue failed (non-fatal)', {
          correlationId: req.requestId,
          componentId: String(finalComponent._id),
          error: notifyErr instanceof Error ? notifyErr.message : String(notifyErr),
        });
      }

      successResponse(res, {
        component: serializeComponent(finalComponent),
        crossedWarning,
        crossedRetirement,
      });
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to log gear usage',
        err instanceof Error ? err.message : String(err),
      );
    }
  },
);

// POST /gear/:id/retire — explicit user retirement
router.post('/:id/retire', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId(getUserId(req));
    const id = req.params.id as string;
    if (!Types.ObjectId.isValid(id)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid gear id');
      return;
    }

    const component = await GearComponent.findOneAndUpdate(
      { _id: new Types.ObjectId(id), userId },
      { $set: { status: 'retired', retiredAt: new Date() } },
      { new: true },
    );

    if (!component) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Gear component not found');
      return;
    }

    try {
      await EventLog.create({
        userId,
        eventType: 'GearRetired',
        metadata: {
          componentId: String(component._id),
          autoRetired: false,
        },
        source: 'ios',
      });
    } catch (logErr) {
      logger.warn('Gear retired event log failed (non-fatal)', {
        correlationId: req.requestId,
        componentId: String(component._id),
        error: logErr instanceof Error ? logErr.message : String(logErr),
      });
    }

    successResponse(res, serializeComponent(component));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to retire gear',
      err instanceof Error ? err.message : String(err),
    );
  }
});

function formatValue(value: number): string {
  if (Number.isInteger(value)) {
    return String(value);
  }
  return value.toFixed(1);
}

export default router;
