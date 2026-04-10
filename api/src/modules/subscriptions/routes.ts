import { Router, type Request, type Response } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { StatusCodes } from 'http-status-codes';
import {
  validateAppleTransaction,
  getSubscriptionForUser,
} from './subscriptionService.js';

const router = Router();

// GET /subscriptions — current user's subscription status
router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = req.user!.sub;
    const subscription = await getSubscriptionForUser(userId);

    if (!subscription) {
      successResponse(res, {
        status: 'none',
        tier: 'free',
        expiresAt: null,
        extensionDays: 0,
        autoRenew: false,
        platform: null,
      });
      return;
    }

    successResponse(res, {
      status: subscription.status,
      tier: 'annual',
      expiresAt: subscription.expiryDate,
      extensionDays: subscription.extensionDays,
      autoRenew: subscription.status === 'active',
      platform: subscription.provider,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Failed to fetch subscription';
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, message);
  }
});

// POST /subscriptions/validate-apple — validate a StoreKit 2 JWS transaction
router.post('/validate-apple', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const { jwsRepresentation } = req.body as { jwsRepresentation?: string };

    if (!jwsRepresentation || typeof jwsRepresentation !== 'string') {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'jwsRepresentation is required');
      return;
    }

    const userId = req.user!.sub;
    const result = await validateAppleTransaction(jwsRepresentation, userId);

    successResponse(res, {
      status: result.status,
      expiryDate: result.expiryDate.toISOString(),
      extensionDays: result.extensionDays,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Validation failed';
    errorResponse(res, StatusCodes.BAD_REQUEST, message);
  }
});

// POST /subscriptions — create subscription (stub for Stripe web flow)
router.post('/', isAuthenticated, (_req: Request, res: Response) => {
  successResponse(res, { message: 'Create subscription — not yet implemented' }, 501);
});

// PATCH /subscriptions — update subscription
router.patch('/', isAuthenticated, (_req: Request, res: Response) => {
  successResponse(res, { message: 'Update subscription — not yet implemented' }, 501);
});

// DELETE /subscriptions — cancel subscription
router.delete('/', isAuthenticated, (_req: Request, res: Response) => {
  successResponse(res, { message: 'Cancel subscription — not yet implemented' }, 501);
});

export default router;
