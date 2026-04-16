import { Router, type Request, type Response } from 'express';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { StatusCodes } from 'http-status-codes';
import {
  validateAppleTransaction,
  getSubscriptionForUser,
  getSubscriptionPlanFromProductId,
  getSubscriptionTierFromProductId,
} from './subscriptionService.js';
import {
  processOutstandingReferralRewardsForReferrer,
  processReferralQualificationForReferredUser,
} from '../referrals/referralService.js';

const router = Router();

async function respondWithCurrentSubscription(req: Request, res: Response) {
  try {
    const userId = req.user!.sub;
    const subscription = await getSubscriptionForUser(userId);

    if (!subscription) {
      successResponse(res, {
        status: 'none',
        tier: 'free',
        plan: null,
        purchaseDate: null,
        expiresAt: null,
        extensionDays: 0,
        autoRenew: false,
        platform: null,
      });
      return;
    }

    successResponse(res, {
      status: subscription.status,
      tier: getSubscriptionTierFromProductId(subscription.productId),
      plan: getSubscriptionPlanFromProductId(subscription.productId),
      purchaseDate: subscription.purchaseDate,
      expiresAt: subscription.expiryDate,
      extensionDays: subscription.extensionDays,
      autoRenew:
        subscription.status === 'active'
        && getSubscriptionTierFromProductId(subscription.productId) !== 'lifetime',
      platform: subscription.provider,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Failed to fetch subscription';
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, message);
  }
}

// GET /subscriptions — current user's subscription status
router.get('/', isAuthenticated, respondWithCurrentSubscription);

// GET /subscriptions/me — backward-compatible alias for older clients
router.get('/me', isAuthenticated, respondWithCurrentSubscription);

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

    await processReferralQualificationForReferredUser(userId);
    await processOutstandingReferralRewardsForReferrer(userId);

    const currentSubscription = await getSubscriptionForUser(userId);
    const subscription = currentSubscription ?? {
      status: result.status,
      productId: result.productId,
      provider: result.provider,
      purchaseDate: result.purchaseDate,
      expiryDate: result.expiryDate,
      extensionDays: result.extensionDays,
    };

    successResponse(res, {
      status: subscription.status,
      tier: getSubscriptionTierFromProductId(subscription.productId),
      plan: getSubscriptionPlanFromProductId(subscription.productId),
      purchaseDate: subscription.purchaseDate.toISOString(),
      expiryDate: subscription.expiryDate.toISOString(),
      extensionDays: subscription.extensionDays,
      platform: subscription.provider,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Validation failed';
    errorResponse(res, StatusCodes.BAD_REQUEST, message);
  }
});

// ─── Stripe Web Subscription Flow ─────────────────────────────────────────

const STRIPE_PRICE_MAP: Record<string, { tier: string; plan: string; price: number }> = {
  hustle: { tier: 'monthly', plan: 'HUSTLE', price: 499 },
  hwmf: { tier: 'annual', plan: 'HWMF', price: 6000 },
  babyMomma: { tier: 'lifetime', plan: 'BABY MOMMA', price: 9900 },
};

// POST /subscriptions — create Stripe Checkout session
router.post('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const { tier, successUrl } = req.body as {
      tier?: string;
      successUrl?: string;
      cancelUrl?: string;
    };

    if (!tier || !STRIPE_PRICE_MAP[tier]) {
      errorResponse(res, StatusCodes.BAD_REQUEST, `Invalid tier. Must be one of: ${Object.keys(STRIPE_PRICE_MAP).join(', ')}`);
      return;
    }

    const plan = STRIPE_PRICE_MAP[tier];

    // TODO: Replace with actual Stripe Checkout session creation
    // const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
    // const session = await stripe.checkout.sessions.create({
    //   mode: plan.tier === 'lifetime' ? 'payment' : 'subscription',
    //   line_items: [{ price: plan.stripePriceId, quantity: 1 }],
    //   success_url: successUrl,
    //   cancel_url: cancelUrl,
    //   client_reference_id: userId,
    //   metadata: { tier, userId },
    // });

    successResponse(res, {
      checkoutUrl: successUrl || '/account',
      tier: plan.plan,
      price: plan.price / 100,
      currency: 'USD',
      message: 'Stripe Checkout integration pending — subscription recorded locally',
    }, StatusCodes.CREATED);
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to create subscription', (err as Error).message);
  }
});

// PATCH /subscriptions — upgrade subscription tier
router.patch('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = req.user!.sub;
    const { tier } = req.body as { tier?: string };

    if (!tier || !STRIPE_PRICE_MAP[tier]) {
      errorResponse(res, StatusCodes.BAD_REQUEST, `Invalid tier. Must be one of: ${Object.keys(STRIPE_PRICE_MAP).join(', ')}`);
      return;
    }

    const currentSub = await getSubscriptionForUser(userId);
    if (!currentSub) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'No active subscription to upgrade');
      return;
    }

    const plan = STRIPE_PRICE_MAP[tier];

    // TODO: Call Stripe to update the subscription
    // await stripe.subscriptions.update(currentSub.stripeSubscriptionId, { items: [{ price: newPriceId }] });

    successResponse(res, {
      tier: plan.plan,
      price: plan.price / 100,
      message: 'Stripe upgrade integration pending',
    });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to upgrade subscription', (err as Error).message);
  }
});

// DELETE /subscriptions — cancel subscription
router.delete('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = req.user!.sub;
    const currentSub = await getSubscriptionForUser(userId);

    if (!currentSub) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'No active subscription to cancel');
      return;
    }

    // TODO: Call Stripe to cancel
    // await stripe.subscriptions.cancel(currentSub.stripeSubscriptionId);

    successResponse(res, {
      status: 'cancelled',
      message: 'Stripe cancellation integration pending',
    });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to cancel subscription', (err as Error).message);
  }
});

export default router;
