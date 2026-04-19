import type { Stripe } from 'stripe/cjs/stripe.core.js';
import { Types } from 'mongoose';
import { Subscription, type ISubscription } from '../../models/Subscription.js';
import { User } from '../../models/User.js';
import { ProcessedWebhookEvent } from '../../models/ProcessedWebhookEvent.js';
import logger from '../../utils/logger.js';
import { handleCheckoutSessionCompleted } from './checkoutService.js';
// Backlog item #39 — achievement badges (first_purchase trigger).
// Read-only subscribe into the charge path; see `handleInvoicePaid` below.
import { checkAndAwardFor } from '../achievements/service.js';

/**
 * Stripe subscription lifecycle webhook handlers.
 *
 * These handlers keep our Mongo `Subscription` records in sync with
 * Stripe-side state for the web/Stripe subscription flow. They are
 * orthogonal to the Apple StoreKit flow (see validateAppleTransaction).
 *
 * Events handled:
 *   customer.subscription.created   → upsert active subscription
 *   customer.subscription.updated   → reflect status / cancel_at_period_end / period change
 *   customer.subscription.deleted   → final cancellation transition
 *   invoice.paid                    → bump expiryDate from period_end (renewal)
 *   invoice.payment_succeeded       → alias of invoice.paid
 *   invoice.payment_failed          → set status='past_due'
 *   invoice.finalized               → audit log only
 */

const HANDLED_EVENT_TYPES = new Set<string>([
  'checkout.session.completed',
  'customer.subscription.created',
  'customer.subscription.updated',
  'customer.subscription.deleted',
  'invoice.paid',
  'invoice.payment_succeeded',
  'invoice.payment_failed',
  'invoice.finalized',
]);

export function isStripeSubscriptionEvent(type: string): boolean {
  return HANDLED_EVENT_TYPES.has(type);
}

/**
 * Record an event as processed. Returns `true` if this is a new event,
 * `false` if it was already processed (duplicate delivery).
 *
 * Two-stage dedupe — mirrors the Apple ASSN v2 pattern in
 * `appleServerNotifications.ts`:
 *   1. Query `ProcessedWebhookEvent` by (provider, eventId). If present,
 *      short-circuit — regardless of whether the unique index has been
 *      built yet (relevant under mongoose autoIndex in tests / cold
 *      startup, where the index can lag behind the first insert).
 *   2. Otherwise insert; an E11000 from a concurrent writer (Stripe
 *      retries in parallel) is also treated as "already processed".
 *
 * The query-first step is what makes this robust to index-creation lag:
 * a pure `create`-with-E11000 catch silently re-processes duplicates
 * whenever the unique index is still being built in the background.
 */
export async function claimWebhookEvent(event: Stripe.Event): Promise<boolean> {
  const existing = await ProcessedWebhookEvent.findOne({
    provider: 'stripe',
    eventId: event.id,
  }).lean();
  if (existing) {
    return false;
  }

  try {
    await ProcessedWebhookEvent.create({
      eventId: event.id,
      provider: 'stripe',
      type: event.type,
    });
    return true;
  } catch (err) {
    const code = (err as { code?: number }).code;
    if (code === 11000) {
      // Concurrent duplicate — already recorded by a parallel retry.
      return false;
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

type SubscriptionLike = Stripe.Subscription & {
  current_period_end?: number;
  current_period_start?: number;
  cancel_at_period_end?: boolean;
};

async function resolveUserIdFromStripe(
  customerId: string | Stripe.Customer | Stripe.DeletedCustomer | null | undefined,
  metadataUserId: string | undefined | null,
): Promise<string | null> {
  if (metadataUserId && Types.ObjectId.isValid(metadataUserId)) {
    return metadataUserId;
  }

  if (!customerId) {
    return null;
  }

  const cid = typeof customerId === 'string' ? customerId : customerId.id;
  if (!cid) return null;

  const user = await User.findOne({ stripeCustomerId: cid }).select('_id').lean();
  if (user?._id) {
    return user._id.toString();
  }
  return null;
}

function stripeStatusToLocal(
  stripeStatus: Stripe.Subscription.Status,
  cancelAtPeriodEnd: boolean,
): ISubscription['status'] {
  switch (stripeStatus) {
    case 'active':
    case 'trialing':
      return 'active';
    case 'past_due':
      return 'past_due';
    case 'unpaid':
      return 'past_due';
    case 'canceled':
    case 'incomplete_expired':
      return 'cancelled';
    case 'incomplete':
      return 'expired';
    case 'paused':
      return 'grace_period';
    default:
      return cancelAtPeriodEnd ? 'active' : 'expired';
  }
}

function productIdFromSubscription(sub: Stripe.Subscription): string {
  const firstItem = sub.items?.data?.[0];
  const price = firstItem?.price as Stripe.Price | undefined;
  if (!price) {
    return sub.id;
  }
  if (typeof price.product === 'string') {
    return price.product;
  }
  if (price.product && typeof price.product === 'object' && 'id' in price.product) {
    return price.product.id;
  }
  return price.id ?? sub.id;
}

function toDateFromUnix(seconds: number | undefined | null): Date | null {
  if (!seconds || Number.isNaN(seconds)) return null;
  return new Date(seconds * 1000);
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async function handleSubscriptionCreated(
  sub: SubscriptionLike,
): Promise<void> {
  const userId = await resolveUserIdFromStripe(
    sub.customer,
    sub.metadata?.userId,
  );
  if (!userId) {
    logger.warn('Stripe subscription.created for unknown user', {
      subscriptionId: sub.id,
      customer: typeof sub.customer === 'string' ? sub.customer : sub.customer?.id,
    });
    return;
  }

  const productId = productIdFromSubscription(sub);
  const purchaseDate =
    toDateFromUnix(sub.current_period_start ?? sub.start_date) ?? new Date();
  const expiryDate =
    toDateFromUnix(sub.current_period_end) ??
    new Date(purchaseDate.getTime() + 30 * 24 * 60 * 60 * 1000);
  const status = stripeStatusToLocal(sub.status, sub.cancel_at_period_end ?? false);

  await Subscription.findOneAndUpdate(
    {
      provider: 'stripe',
      providerOriginalTransactionId: sub.id,
    },
    {
      $set: {
        userId: new Types.ObjectId(userId),
        provider: 'stripe',
        providerOriginalTransactionId: sub.id,
        stripeSubscriptionId: sub.id,
        stripeCustomerId:
          typeof sub.customer === 'string' ? sub.customer : sub.customer?.id ?? null,
        productId,
        status,
        purchaseDate,
        expiryDate,
        lastValidatedAt: new Date(),
        autoRenew: !(sub.cancel_at_period_end ?? false),
        cancelledAt: null,
      },
      $setOnInsert: { extensionDays: 0 },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  );

  logger.info('Stripe subscription created', {
    subscriptionId: sub.id,
    userId,
    status,
  });
}

async function handleSubscriptionUpdated(
  sub: SubscriptionLike,
): Promise<void> {
  const userId = await resolveUserIdFromStripe(
    sub.customer,
    sub.metadata?.userId,
  );
  if (!userId) {
    logger.warn('Stripe subscription.updated for unknown user', {
      subscriptionId: sub.id,
    });
    return;
  }

  const status = stripeStatusToLocal(sub.status, sub.cancel_at_period_end ?? false);
  const expiryDate =
    toDateFromUnix(sub.current_period_end) ??
    toDateFromUnix(sub.cancel_at) ??
    null;
  const autoRenew = !(sub.cancel_at_period_end ?? false) && status !== 'cancelled';

  const update: Record<string, unknown> = {
    status,
    autoRenew,
    lastValidatedAt: new Date(),
    stripeCustomerId:
      typeof sub.customer === 'string' ? sub.customer : sub.customer?.id ?? null,
  };
  if (expiryDate) update.expiryDate = expiryDate;
  if (status === 'cancelled') update.cancelledAt = new Date();

  const result = await Subscription.findOneAndUpdate(
    {
      provider: 'stripe',
      providerOriginalTransactionId: sub.id,
    },
    {
      $set: update,
      $setOnInsert: {
        userId: new Types.ObjectId(userId),
        provider: 'stripe',
        providerOriginalTransactionId: sub.id,
        stripeSubscriptionId: sub.id,
        productId: productIdFromSubscription(sub),
        purchaseDate:
          toDateFromUnix(sub.current_period_start ?? sub.start_date) ?? new Date(),
        extensionDays: 0,
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  );

  logger.info('Stripe subscription updated', {
    subscriptionId: sub.id,
    userId,
    status,
    autoRenew,
    cancelAtPeriodEnd: sub.cancel_at_period_end,
    localId: result?._id?.toString(),
  });
}

async function handleSubscriptionDeleted(
  sub: SubscriptionLike,
): Promise<void> {
  const updated = await Subscription.findOneAndUpdate(
    {
      provider: 'stripe',
      providerOriginalTransactionId: sub.id,
    },
    {
      $set: {
        status: 'cancelled',
        autoRenew: false,
        cancelledAt: new Date(),
        lastValidatedAt: new Date(),
      },
    },
    { new: true },
  );

  if (!updated) {
    logger.warn('Stripe subscription.deleted for unknown local subscription', {
      subscriptionId: sub.id,
    });
    return;
  }

  logger.info('Stripe subscription deleted', {
    subscriptionId: sub.id,
    userId: updated.userId.toString(),
  });
}

async function handleInvoicePaid(invoice: Stripe.Invoice): Promise<void> {
  const invoiceWithSub = invoice as Stripe.Invoice & {
    subscription?: string | Stripe.Subscription | null;
    lines: Stripe.ApiList<
      Stripe.InvoiceLineItem & { period?: { start?: number; end?: number } }
    >;
  };

  const subId =
    typeof invoiceWithSub.subscription === 'string'
      ? invoiceWithSub.subscription
      : invoiceWithSub.subscription?.id ?? null;

  if (!subId) {
    // Not a subscription invoice — ignore silently.
    return;
  }

  // Prefer the subscription line-item period.end (definitive new period end)
  // and fall back to invoice.period_end.
  const lineItem = invoiceWithSub.lines?.data?.find(
    (line) => line.period?.end,
  );
  const newExpiry =
    toDateFromUnix(lineItem?.period?.end ?? null) ??
    toDateFromUnix(invoice.period_end) ??
    null;

  const update: Record<string, unknown> = {
    status: 'active',
    lastValidatedAt: new Date(),
  };
  if (newExpiry) update.expiryDate = newExpiry;

  const result = await Subscription.findOneAndUpdate(
    {
      provider: 'stripe',
      providerOriginalTransactionId: subId,
    },
    { $set: update },
    { new: true },
  );

  if (!result) {
    logger.warn('Stripe invoice.paid for unknown local subscription', {
      subscriptionId: subId,
      invoiceId: invoice.id,
    });
    return;
  }

  logger.info('Stripe invoice paid — subscription renewed', {
    subscriptionId: subId,
    invoiceId: invoice.id,
    userId: result.userId.toString(),
    newExpiry: newExpiry?.toISOString() ?? null,
  });

  // Backlog item #39 — first_purchase achievement hook. Idempotent via the
  // unique index on Achievement(userId, badgeId) so renewals are no-ops.
  await checkAndAwardFor(result.userId, 'subscriptionCharged');
}

async function handleInvoicePaymentFailed(
  invoice: Stripe.Invoice,
): Promise<void> {
  const invoiceWithSub = invoice as Stripe.Invoice & {
    subscription?: string | Stripe.Subscription | null;
  };
  const subId =
    typeof invoiceWithSub.subscription === 'string'
      ? invoiceWithSub.subscription
      : invoiceWithSub.subscription?.id ?? null;

  if (!subId) {
    return;
  }

  const result = await Subscription.findOneAndUpdate(
    {
      provider: 'stripe',
      providerOriginalTransactionId: subId,
    },
    {
      $set: {
        status: 'past_due',
        lastValidatedAt: new Date(),
      },
    },
    { new: true },
  );

  if (!result) {
    logger.warn('Stripe invoice.payment_failed for unknown local subscription', {
      subscriptionId: subId,
      invoiceId: invoice.id,
    });
    return;
  }

  logger.warn('Stripe invoice payment failed — marked past_due', {
    subscriptionId: subId,
    invoiceId: invoice.id,
    userId: result.userId.toString(),
  });
}

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

/**
 * Dispatch a Stripe event that belongs to the subscription lifecycle.
 * Caller is responsible for signature verification and idempotency.
 */
export async function dispatchStripeSubscriptionEvent(
  event: Stripe.Event,
): Promise<void> {
  switch (event.type) {
    case 'checkout.session.completed': {
      await handleCheckoutSessionCompleted(
        event.data.object as Stripe.Checkout.Session,
      );
      return;
    }
    case 'customer.subscription.created': {
      await handleSubscriptionCreated(
        event.data.object as SubscriptionLike,
      );
      return;
    }
    case 'customer.subscription.updated': {
      await handleSubscriptionUpdated(
        event.data.object as SubscriptionLike,
      );
      return;
    }
    case 'customer.subscription.deleted': {
      await handleSubscriptionDeleted(
        event.data.object as SubscriptionLike,
      );
      return;
    }
    case 'invoice.paid':
    case 'invoice.payment_succeeded': {
      await handleInvoicePaid(event.data.object as Stripe.Invoice);
      return;
    }
    case 'invoice.payment_failed': {
      await handleInvoicePaymentFailed(event.data.object as Stripe.Invoice);
      return;
    }
    case 'invoice.finalized': {
      const invoice = event.data.object as Stripe.Invoice;
      logger.info('Stripe invoice finalized (audit-only)', {
        invoiceId: invoice.id,
        customer:
          typeof invoice.customer === 'string'
            ? invoice.customer
            : invoice.customer?.id,
      });
      return;
    }
    default: {
      // Not a subscription event — dispatcher-level no-op.
      return;
    }
  }
}
