import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, hasRole } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { User } from '../../models/User.js';
import { getFeatureFlagService } from './index.js';
import { getSubscriptionForUser, getSubscriptionTierFromProductId } from '../subscriptions/subscriptionService.js';

// Flag names are kebab-case-or-camelCase, alphanumerics + `-` / `_` / `.`.
// Keeping this tight prevents accidental Redis keyspace injection via the
// `name` URL parameter (e.g. `foo:other` that could escape the `ff:flag:`
// namespace).
const flagNamePattern = /^[a-zA-Z0-9][a-zA-Z0-9_.\-]{0,63}$/;
const flagNameSchema = z.string().regex(flagNamePattern, 'Invalid flag name');
const flagValueSchema = z.object({ value: z.boolean() });
const overrideBodySchema = z.object({
  value: z.boolean(),
  userId: z.string().min(1).optional(),
  tier: z.string().min(1).optional(),
});

async function resolveUserTier(userId: string): Promise<string | null> {
  const subscription = await getSubscriptionForUser(userId);
  if (!subscription) {
    return null;
  }
  return getSubscriptionTierFromProductId(subscription.productId);
}

// ---------------------------------------------------------------------------
// Admin router — mounted at `/admin/feature-flags`. Every route requires the
// `admin` role (enforced via `router.use` below).
// ---------------------------------------------------------------------------
const adminRouter = Router();
adminRouter.use(isAuthenticated, hasRole(['admin']));

adminRouter.get('/', async (_req: Request, res: Response) => {
  try {
    const service = getFeatureFlagService();
    const flags = await service.resolveAllForUser(null);
    successResponse(res, { flags });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list feature flags',
      (err as Error).message,
    );
  }
});

adminRouter.get('/:name', async (req: Request, res: Response) => {
  const name = flagNameSchema.safeParse(req.params.name);
  if (!name.success) {
    errorResponse(res, StatusCodes.BAD_REQUEST, name.error.errors[0]?.message ?? 'Invalid flag name');
    return;
  }

  try {
    const service = getFeatureFlagService();
    const value = await service.getGlobal(name.data);
    successResponse(res, { name: name.data, value: value ?? null });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to read feature flag',
      (err as Error).message,
    );
  }
});

adminRouter.put(
  '/:name',
  validateBody(overrideBodySchema),
  async (req: Request, res: Response) => {
    const name = flagNameSchema.safeParse(req.params.name);
    if (!name.success) {
      errorResponse(res, StatusCodes.BAD_REQUEST, name.error.errors[0]?.message ?? 'Invalid flag name');
      return;
    }

    const body = req.body as z.infer<typeof overrideBodySchema>;
    try {
      const service = getFeatureFlagService();

      if (body.userId && body.tier) {
        errorResponse(
          res,
          StatusCodes.BAD_REQUEST,
          'Specify either userId or tier, not both',
        );
        return;
      }

      if (body.userId) {
        await service.setUserOverride(body.userId, name.data, body.value);
        successResponse(res, {
          name: name.data,
          scope: 'user',
          userId: body.userId,
          value: body.value,
        });
        return;
      }

      if (body.tier) {
        await service.setTierOverride(body.tier, name.data, body.value);
        successResponse(res, {
          name: name.data,
          scope: 'tier',
          tier: body.tier,
          value: body.value,
        });
        return;
      }

      await service.setGlobal(name.data, body.value);
      successResponse(res, { name: name.data, scope: 'global', value: body.value });
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update feature flag',
        (err as Error).message,
      );
    }
  },
);

adminRouter.delete('/:name', async (req: Request, res: Response) => {
  const name = flagNameSchema.safeParse(req.params.name);
  if (!name.success) {
    errorResponse(res, StatusCodes.BAD_REQUEST, name.error.errors[0]?.message ?? 'Invalid flag name');
    return;
  }

  const scope = (req.query.scope as string | undefined) ?? 'global';
  const userId = req.query.userId as string | undefined;
  const tier = req.query.tier as string | undefined;

  try {
    const service = getFeatureFlagService();

    if (scope === 'user') {
      if (!userId) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'userId query param required for scope=user');
        return;
      }
      await service.deleteUserOverride(userId, name.data);
      successResponse(res, { name: name.data, scope: 'user', userId, deleted: true });
      return;
    }

    if (scope === 'tier') {
      if (!tier) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'tier query param required for scope=tier');
        return;
      }
      await service.deleteTierOverride(tier, name.data);
      successResponse(res, { name: name.data, scope: 'tier', tier, deleted: true });
      return;
    }

    await service.deleteGlobal(name.data);
    successResponse(res, { name: name.data, scope: 'global', deleted: true });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to delete feature flag',
      (err as Error).message,
    );
  }
});

// Note: also expose the single-flag endpoints in a way that lets the admin
// write a global with just a body — this is the primary "flip a flag"
// surface called by the web console. The validated body is `{ value: true }`
// (no userId/tier) which lands on the global branch above.
adminRouter.put('/:name/value', validateBody(flagValueSchema), async (req: Request, res: Response) => {
  const name = flagNameSchema.safeParse(req.params.name);
  if (!name.success) {
    errorResponse(res, StatusCodes.BAD_REQUEST, name.error.errors[0]?.message ?? 'Invalid flag name');
    return;
  }
  const { value } = req.body as z.infer<typeof flagValueSchema>;
  try {
    const service = getFeatureFlagService();
    await service.setGlobal(name.data, value);
    successResponse(res, { name: name.data, scope: 'global', value });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to update feature flag',
      (err as Error).message,
    );
  }
});

// ---------------------------------------------------------------------------
// User router — mounted at `/feature-flags`. Returns the resolved flag map
// for the authenticated caller (per-user > per-tier > global > default).
// ---------------------------------------------------------------------------
const userRouter = Router();
userRouter.use(isAuthenticated);

userRouter.get('/', async (req: Request, res: Response) => {
  try {
    const userId = req.user!.sub;
    const user = await User.findById(userId).select('_id').lean();
    if (!user) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    const tier = await resolveUserTier(userId);
    const service = getFeatureFlagService();
    const flags = await service.resolveAllForUser({ id: userId, tier });
    successResponse(res, { flags, tier });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load feature flags',
      (err as Error).message,
    );
  }
});

export { adminRouter, userRouter };
