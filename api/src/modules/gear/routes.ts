import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { User } from '../../models/User.js';
import { GearComponent } from '../../models/GearComponent.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

/**
 * Backlog item #9 — Strava-style "default gear per activity type".
 *
 * Exposes:
 *   GET  /api/v1/gear/default-for-activity?type=<activityType>
 *   PUT  /api/v1/gear/default-for-activity   (body: { activityType, gearId })
 *
 * The fuller GearComponent CRUD ships with PR #55; this file is the thin
 * slice needed to wire up auto-attach on workout/run start.
 */

// Activity types we accept for the default-gear map. Kept permissive —
// Apple adds new HKWorkoutActivityType values each WWDC and we want to
// forward-compat without a model migration.
const ACTIVITY_TYPE_PATTERN = /^[a-zA-Z][a-zA-Z0-9_]{0,63}$/;

const setDefaultGearSchema = z.object({
  activityType: z.string().trim().regex(ACTIVITY_TYPE_PATTERN, 'activityType must be camelCase alphanumeric'),
  gearId: z.union([
    z.string().regex(/^[a-fA-F0-9]{24}$/, 'gearId must be a 24-char hex ObjectId'),
    z.null(),
  ]),
});

function serializeGear(gear: Record<string, any> | null | undefined) {
  if (!gear) {
    return null;
  }
  return {
    _id: String(gear._id),
    name: gear.name,
    kind: gear.kind,
    unit: gear.unit,
    currentValue: gear.currentValue ?? 0,
    retirementThreshold: gear.retirementThreshold ?? null,
    retiredAt: gear.retiredAt ?? null,
  };
}

// GET /gear/default-for-activity?type=running
router.get('/default-for-activity', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const raw = typeof req.query.type === 'string' ? req.query.type.trim() : '';

    if (!raw || !ACTIVITY_TYPE_PATTERN.test(raw)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'type query parameter is required');
      return;
    }

    const user = await User.findById(userId).select('preferences').lean();
    const map = (user?.preferences?.defaultGearByActivity ?? {}) as Record<string, unknown>;
    const rawId = map[raw];

    if (!rawId) {
      successResponse(res, { activityType: raw, gear: null });
      return;
    }

    const id = typeof rawId === 'string' ? rawId : String(rawId);
    if (!Types.ObjectId.isValid(id)) {
      successResponse(res, { activityType: raw, gear: null });
      return;
    }

    const gear = await GearComponent.findOne({
      _id: new Types.ObjectId(id),
      userId,
    }).lean();

    successResponse(res, {
      activityType: raw,
      gear: serializeGear(gear ?? null),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load default gear',
      (err as Error).message,
    );
  }
});

// PUT /gear/default-for-activity  { activityType, gearId }
router.put(
  '/default-for-activity',
  isAuthenticated,
  validateBody(setDefaultGearSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const body = req.body as z.infer<typeof setDefaultGearSchema>;

      const user = await User.findById(userId);
      if (!user) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
        return;
      }

      // Validate that the referenced gear belongs to the user when setting.
      if (body.gearId) {
        const gear = await GearComponent.findOne({
          _id: new Types.ObjectId(body.gearId),
          userId,
        }).lean();

        if (!gear) {
          errorResponse(res, StatusCodes.BAD_REQUEST, 'Gear not found for this user');
          return;
        }
      }

      const existingPreferences = user.preferences ?? {
        pushEnabled: false,
        panicAlertsEnabled: false,
        disconnectAlertsEnabled: false,
        custom: {},
        defaultGearByActivity: {},
      };

      const existingMap = (
        existingPreferences.defaultGearByActivity ?? {}
      ) as Record<string, Types.ObjectId | null>;

      const nextMap: Record<string, Types.ObjectId | null> = { ...existingMap };
      if (body.gearId === null) {
        delete nextMap[body.activityType];
      } else {
        nextMap[body.activityType] = new Types.ObjectId(body.gearId);
      }

      user.preferences = {
        pushEnabled: existingPreferences.pushEnabled ?? false,
        panicAlertsEnabled: existingPreferences.panicAlertsEnabled ?? false,
        disconnectAlertsEnabled: existingPreferences.disconnectAlertsEnabled ?? false,
        custom: existingPreferences.custom ?? {},
        defaultGearByActivity: nextMap,
      };

      // Tell Mongoose the Mixed path changed — otherwise nested field
      // mutations on Schema.Types.Mixed aren't persisted on .save().
      user.markModified('preferences.defaultGearByActivity');
      await user.save();

      successResponse(res, {
        activityType: body.activityType,
        gearId: body.gearId,
      });
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update default gear',
        (err as Error).message,
      );
    }
  },
);

// GET /gear — list the user's gear components (needed by the iOS picker
// in DefaultGearPerActivityView). Minimal read-only surface.
router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const gear = await GearComponent.find({ userId })
      .sort({ retiredAt: 1, kind: 1, name: 1 })
      .lean();
    successResponse(res, gear.map((g) => serializeGear(g)).filter(Boolean));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list gear',
      (err as Error).message,
    );
  }
});

export default router;
