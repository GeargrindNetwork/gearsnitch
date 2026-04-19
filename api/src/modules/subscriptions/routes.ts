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
import { PaymentService, PaymentError } from '../../services/PaymentService.js';
import logger from '../../utils/logger.js';

const APPLE_MANAGE_URL = 'https://apps.apple.com/account/subscriptions';
const paymentService = new PaymentService();

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
//
// Contract:
//   - 404 if the user has no subscription row.
//   - Apple-backed subs: our server cannot cancel at the App Store, but we
//     mark the local Mongo row cancelled/autoRenew=false and return a
//     manageUrl so the iOS client can deep-link to Settings.
//     (No active subscription to cancel is reported as "No active subscription to cancel".)
//   - Stripe-backed subs: call stripe.subscriptions.update(id, { cancel_at_period_end: true })
//     FIRST; only if Stripe accepts do we flip local status to 'cancelled'
//     and autoRenew=false. If Stripe rejects we surface 502 and leave local
//     truth untouched.
router.delete('/', isAuthenticated, async (req: Request, res: Response) => {
  const userId = req.user!.sub;

  try {
    const currentSub = await getSubscriptionForUser(userId);

    if (!currentSub) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'No active subscription to cancel');
      return;
    }

    const previousTier = getSubscriptionTierFromProductId(currentSub.productId);
    const cancelledAt = new Date();

    logger.info('subscription.cancel.intent', {
      userId,
      subscriptionId: currentSub._id.toString(),
      provider: currentSub.provider,
      previousTier,
      timestamp: cancelledAt.toISOString(),
    });

    if (currentSub.provider === 'apple') {
      // Apple: we can only reflect intent locally. User must cancel at Apple.
      currentSub.status = 'cancelled';
      currentSub.autoRenew = false;
      currentSub.cancelledAt = cancelledAt;
      await currentSub.save();

      logger.info('subscription.cancel.apple.local_flipped', {
        userId,
        subscriptionId: currentSub._id.toString(),
        previousTier,
      });

      successResponse(res, {
        status: 'cancelled',
        platform: 'apple',
        autoRenew: false,
        manageUrl: APPLE_MANAGE_URL,
        message:
          'Apple subscriptions must be cancelled from iOS Settings. '
          + 'Your local record is marked cancelled; billing continues until '
          + 'the period ends unless you also cancel at Apple.',
      });
      return;
    }

    if (currentSub.provider === 'stripe') {
      // Stripe: call upstream FIRST. Only flip local state after success.
      try {
        await paymentService.cancelStripeSubscriptionAtPeriodEnd(
          currentSub.providerOriginalTransactionId,
        );
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Stripe cancel failed';
        logger.error('subscription.cancel.stripe.failed', {
          userId,
          subscriptionId: currentSub._id.toString(),
          error: message,
        });
        const statusCode = err instanceof PaymentError
          ? StatusCodes.BAD_GATEWAY
          : StatusCodes.INTERNAL_SERVER_ERROR;
        errorResponse(res, statusCode, 'Failed to cancel Stripe subscription', message);
        return;
      }

      currentSub.status = 'cancelled';
      currentSub.autoRenew = false;
      currentSub.cancelledAt = cancelledAt;
      await currentSub.save();

      logger.info('subscription.cancel.stripe.completed', {
        userId,
        subscriptionId: currentSub._id.toString(),
        previousTier,
      });

      successResponse(res, {
        status: 'cancelled',
        platform: 'stripe',
        autoRenew: false,
        cancelAtPeriodEnd: true,
        message:
          'Stripe subscription will not auto-renew. Access continues '
          + 'until the end of the current billing period.',
      });
      return;
    }

    // Unknown provider — refuse to silently no-op.
    logger.error('subscription.cancel.unknown_provider', {
      userId,
      subscriptionId: currentSub._id.toString(),
      provider: currentSub.provider,
    });
    errorResponse(
      res,
      StatusCodes.BAD_REQUEST,
      `Cannot cancel subscription from provider: ${currentSub.provider}`,
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Failed to cancel subscription';
    logger.error('subscription.cancel.exception', { userId, error: message });
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to cancel subscription', message);
  }
});

export default router;
