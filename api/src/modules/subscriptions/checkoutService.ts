import StripeLib from 'stripe';
import { Stripe } from 'stripe/cjs/stripe.core.js';
import { Types } from 'mongoose';
import config from '../../config/index.js';
import { Subscription } from '../../models/Subscription.js';
import { User } from '../../models/User.js';
import logger from '../../utils/logger.js';

/**
 * Web Stripe Checkout flow (item #28).
 *
 * Apple-side IAP is handled by `validateAppleTransaction` and the App Store
 * Server Notifications pipeline. This module is the equivalent for the
 * externally-discoverable web /subscribe path. Per App Store guideline 3.1.1
 * we must NOT link to this path from inside the iOS binary; web is its own
 * acquisition channel.
 *
 * Lazy-init mirrors `PaymentService` so jest / type-check / lint lanes that
 * never set STRIPE_SECRET_KEY do not throw at module load.
 */

let _stripe: Stripe | null = null;
function stripeClient(): Stripe {
  if (_stripe === null) {
    _stripe = new StripeLib(config.stripeSecretKey) as unknown as Stripe;
  }
  return _stripe;
}
const stripe: Stripe = new Proxy({} as Stripe, {
  get(_target, prop) {
    return Reflect.get(stripeClient() as object, prop);
  },
}) as Stripe;

export type WebSubscriptionTier = 'hustle' | 'hwmf' | 'babyMomma';

interface TierConfig {
  /** Stripe Price ID — sourced from env (created via setup-stripe-products.sh). */
  priceIdEnv: 'stripePriceHustle' | 'stripePriceHwmf' | 'stripePriceBabyMomma';
  /** Stripe Checkout mode — 'subscription' for recurring, 'payment' for lifetime. */
  mode: 'subscription' | 'payment';
  /** Apple-equivalent productId we persist on the local Subscription row. */
  productId: string;
  /** Display label. */
  plan: string;
  /** Tier classification used elsewhere in the app. */
  tier: 'monthly' | 'annual' | 'lifetime';
}

const TIER_CONFIG: Record<WebSubscriptionTier, TierConfig> = {
  hustle: {
    priceIdEnv: 'stripePriceHustle',
    mode: 'subscription',
    productId: 'com.gearsnitch.web.monthly',
    plan: 'HUSTLE',
    tier: 'monthly',
  },
  hwmf: {
    priceIdEnv: 'stripePriceHwmf',
    mode: 'subscription',
    productId: 'com.gearsnitch.web.annual',
    plan: 'HWMF',
    tier: 'annual',
  },
  babyMomma: {
    priceIdEnv: 'stripePriceBabyMomma',
    mode: 'payment',
    productId: 'com.gearsnitch.web.lifetime',
    plan: 'BABY MOMMA',
    tier: 'lifetime',
  },
};

export function isWebSubscriptionTier(value: unknown): value is WebSubscriptionTier {
  return typeof value === 'string' && Object.prototype.hasOwnProperty.call(TIER_CONFIG, value);
}

export function getTierConfig(tier: WebSubscriptionTier): TierConfig {
  return TIER_CONFIG[tier];
}

export interface CreateCheckoutSessionInput {
  userId: string;
  tier: WebSubscriptionTier;
  successUrl: string;
  cancelUrl: string;
}

export interface CreateCheckoutSessionResult {
  checkoutUrl: string;
  sessionId: string;
}

export class CheckoutSessionError extends Error {
  code: string;
  statusCode: number;
  constructor(message: string, code: string, statusCode = 400) {
    super(message);
    this.name = 'CheckoutSessionError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

/**
 * Build and return a Stripe Checkout Session URL the browser should redirect
 * to. Persists `stripeCustomerId` on User the first time a Stripe customer
 * row gets created so subsequent purchases skip the email-lookup.
 */
export async function createSubscriptionCheckoutSession(
  input: CreateCheckoutSessionInput,
): Promise<CreateCheckoutSessionResult> {
  const tierCfg = TIER_CONFIG[input.tier];
  const priceId = config[tierCfg.priceIdEnv];
  if (!priceId) {
    throw new CheckoutSessionError(
      `Stripe price not configured for tier ${input.tier}`,
      'PRICE_NOT_CONFIGURED',
      500,
    );
  }

  const user = await User.findById(input.userId);
  if (!user) {
    throw new CheckoutSessionError('User not found', 'USER_NOT_FOUND', 404);
  }

  const successUrlWithSession = appendSessionPlaceholder(input.successUrl);

  const baseParams: Stripe.Checkout.SessionCreateParams = {
    mode: tierCfg.mode,
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: successUrlWithSession,
    cancel_url: input.cancelUrl,
    client_reference_id: user._id.toString(),
    allow_promotion_codes: true,
    metadata: {
      tier: input.tier,
      userId: user._id.toString(),
    },
  };

  if (user.stripeCustomerId) {
    baseParams.customer = user.stripeCustomerId;
  } else {
    baseParams.customer_email = user.email;
    baseParams.customer_creation = tierCfg.mode === 'payment' ? 'always' : undefined;
  }

  if (tierCfg.mode === 'subscription') {
    baseParams.subscription_data = {
      trial_period_days: 7,
      metadata: {
        tier: input.tier,
        userId: user._id.toString(),
      },
    };
  } else {
    baseParams.payment_intent_data = {
      metadata: {
        tier: input.tier,
        userId: user._id.toString(),
      },
    };
  }

  const session = await stripe.checkout.sessions.create(baseParams);

  if (!session.url) {
    throw new CheckoutSessionError(
      'Stripe returned a session without a URL',
      'NO_SESSION_URL',
      502,
    );
  }

  logger.info('subscription.checkout.session_created', {
    userId: user._id.toString(),
    tier: input.tier,
    mode: tierCfg.mode,
    sessionId: session.id,
  });

  return { checkoutUrl: session.url, sessionId: session.id };
}

function appendSessionPlaceholder(url: string): string {
  // Stripe replaces `{CHECKOUT_SESSION_ID}` server-side. Avoid double-injecting
  // it if the caller already added the param (defensive — UI may evolve).
  if (url.includes('{CHECKOUT_SESSION_ID}')) {
    return url;
  }
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}session_id={CHECKOUT_SESSION_ID}`;
}

// ---------------------------------------------------------------------------
// checkout.session.completed handler
// ---------------------------------------------------------------------------

type CheckoutSessionLike = Stripe.Checkout.Session & {
  subscription?: string | Stripe.Subscription | null;
  payment_intent?: string | Stripe.PaymentIntent | null;
  customer?: string | Stripe.Customer | Stripe.DeletedCustomer | null;
};

/**
 * Persist an active Subscription row immediately on `checkout.session.completed`.
 *
 * We don't strictly NEED to do this — `customer.subscription.created` will
 * follow within seconds — but persisting here lets the SuccessPage poll
 * `GET /subscriptions/me` and find an `active` row without a 20s race.
 *
 * For one-time `payment` mode (lifetime) checkout.session.completed is the
 * ONLY signal — there's no subscription lifecycle, so we MUST persist here.
 */
export async function handleCheckoutSessionCompleted(
  session: CheckoutSessionLike,
): Promise<void> {
  const userId =
    session.metadata?.userId ??
    (typeof session.client_reference_id === 'string' ? session.client_reference_id : null);

  if (!userId || !Types.ObjectId.isValid(userId)) {
    logger.warn('checkout.session.completed without resolvable userId', {
      sessionId: session.id,
      clientReferenceId: session.client_reference_id,
      hasMetadataUserId: !!session.metadata?.userId,
    });
    return;
  }

  const tierRaw = session.metadata?.tier;
  if (!tierRaw || !isWebSubscriptionTier(tierRaw)) {
    logger.warn('checkout.session.completed with unknown tier', {
      sessionId: session.id,
      tier: tierRaw,
    });
    return;
  }

  const tierCfg = TIER_CONFIG[tierRaw];

  const customerId =
    typeof session.customer === 'string'
      ? session.customer
      : session.customer && 'id' in session.customer
        ? session.customer.id
        : null;

  // Persist stripeCustomerId on User for future portal/checkout calls.
  if (customerId) {
    await User.findByIdAndUpdate(
      userId,
      { $set: { stripeCustomerId: customerId } },
      { new: false },
    );
  }

  if (tierCfg.mode === 'subscription') {
    const stripeSubscriptionId =
      typeof session.subscription === 'string'
        ? session.subscription
        : session.subscription?.id ?? null;

    if (!stripeSubscriptionId) {
      logger.warn('checkout.session.completed (subscription mode) missing subscription id', {
        sessionId: session.id,
      });
      return;
    }

    const purchaseDate = new Date();
    // Conservative initial expiry — refined by customer.subscription.created
    // / invoice.paid which arrive moments later. Annual gets 365d, monthly 30d.
    const ms = tierCfg.tier === 'annual' ? 365 * 24 * 60 * 60 * 1000 : 30 * 24 * 60 * 60 * 1000;
    const expiryDate = new Date(purchaseDate.getTime() + ms);

    await Subscription.findOneAndUpdate(
      { provider: 'stripe', providerOriginalTransactionId: stripeSubscriptionId },
      {
        $set: {
          userId: new Types.ObjectId(userId),
          provider: 'stripe',
          providerOriginalTransactionId: stripeSubscriptionId,
          stripeSubscriptionId,
          stripeCustomerId: customerId,
          productId: tierCfg.productId,
          status: 'active',
          autoRenew: true,
          purchaseDate,
          expiryDate,
          lastValidatedAt: new Date(),
        },
        $setOnInsert: { extensionDays: 0 },
      },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    );

    logger.info('subscription.checkout.completed.subscription', {
      userId,
      tier: tierRaw,
      stripeSubscriptionId,
      sessionId: session.id,
    });
    return;
  }

  // Lifetime / one-time payment.
  const paymentIntentId =
    typeof session.payment_intent === 'string'
      ? session.payment_intent
      : session.payment_intent?.id ?? `cs_${session.id}`;
  const purchaseDate = new Date();
  // Lifetime: pick a far-future expiry. Mirrors how Apple lifetime sets the
  // expiry to a sentinel year-2099 date in `validateAppleTransaction`.
  const expiryDate = new Date('2099-12-31T23:59:59Z');

  await Subscription.findOneAndUpdate(
    { provider: 'stripe', providerOriginalTransactionId: paymentIntentId },
    {
      $set: {
        userId: new Types.ObjectId(userId),
        provider: 'stripe',
        providerOriginalTransactionId: paymentIntentId,
        stripeSubscriptionId: null,
        stripeCustomerId: customerId,
        productId: tierCfg.productId,
        status: 'active',
        autoRenew: false,
        purchaseDate,
        expiryDate,
        lastValidatedAt: new Date(),
      },
      $setOnInsert: { extensionDays: 0 },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  );

  logger.info('subscription.checkout.completed.lifetime', {
    userId,
    tier: tierRaw,
    paymentIntentId,
    sessionId: session.id,
  });
}
