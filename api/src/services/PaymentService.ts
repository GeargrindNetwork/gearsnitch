import StripeLib from 'stripe';
import { Stripe } from 'stripe/cjs/stripe.core.js';
import { Types } from 'mongoose';
import config from '../config/index.js';
import { StoreCart } from '../models/StoreCart.js';
import { StoreOrder, type IStoreOrder } from '../models/StoreOrder.js';
import { User } from '../models/User.js';
import logger from '../utils/logger.js';
import {
  claimWebhookEvent,
  dispatchStripeSubscriptionEvent,
  isStripeSubscriptionEvent,
} from '../modules/subscriptions/stripeSubscriptionWebhookService.js';

const TAX_RATE = 0.0825; // 8.25%
const FLAT_SHIPPING = 599; // $5.99 in cents

// Lazy-init: don't construct the Stripe SDK until first use. Avoids
// throwing at module-load when STRIPE_SECRET_KEY is absent (tests, lint,
// type-check, CI lanes that don't actually hit Stripe).
let _stripe: Stripe | null = null;
function stripeClient(): Stripe {
  if (_stripe === null) {
    _stripe = new StripeLib(config.stripeSecretKey) as unknown as Stripe;
  }
  return _stripe;
}
// Backwards-compatible Proxy: existing `stripe.xxx` callsites work
// untouched, but the underlying SDK is only constructed on first access.
const stripe: Stripe = new Proxy({} as Stripe, {
  get(_target, prop) {
    return Reflect.get(stripeClient() as object, prop);
  },
}) as Stripe;

export class PaymentService {
  /**
   * Create a Stripe PaymentIntent from the user's cart.
   */
  async createPaymentIntent(
    userId: string,
    cartId: string,
    shippingAddress: {
      line1: string;
      line2?: string;
      city: string;
      state: string;
      postalCode: string;
      country: string;
    },
  ): Promise<{
    clientSecret: string;
    paymentIntentId: string;
    amount: number;
    currency: string;
  }> {
    const cart = await StoreCart.findOne({
      _id: new Types.ObjectId(cartId),
      userId: new Types.ObjectId(userId),
    });

    if (!cart || cart.items.length === 0) {
      throw new PaymentError('Cart is empty or does not exist', 'CART_EMPTY');
    }

    const user = await User.findById(userId);
    if (!user) {
      throw new PaymentError('User not found', 'USER_NOT_FOUND');
    }

    const stripeCustomerId = await this.getOrCreateStripeCustomer(
      userId,
      user.email,
    );

    const subtotalCents = Math.round(cart.subtotal * 100);
    const taxCents = Math.round(subtotalCents * TAX_RATE);
    const totalCents = subtotalCents + taxCents + FLAT_SHIPPING;

    const idempotencyKey = `pi_${userId}_${cartId}_${Date.now()}`;

    const paymentIntent = await stripe.paymentIntents.create(
      {
        amount: totalCents,
        currency: 'usd',
        customer: stripeCustomerId,
        metadata: {
          userId,
          cartId,
          subtotal: subtotalCents.toString(),
          tax: taxCents.toString(),
          shipping: FLAT_SHIPPING.toString(),
        },
        shipping: {
          name: user.displayName,
          address: {
            line1: shippingAddress.line1,
            line2: shippingAddress.line2 ?? '',
            city: shippingAddress.city,
            state: shippingAddress.state,
            postal_code: shippingAddress.postalCode,
            country: shippingAddress.country,
          },
        },
      },
      { idempotencyKey },
    );

    await this.upsertPendingOrderFromCart({
      userId,
      cart,
      paymentIntentId: paymentIntent.id,
      shippingAddress,
      subtotalCents,
      taxCents,
      shippingCents: FLAT_SHIPPING,
      totalCents,
    });

    return {
      clientSecret: paymentIntent.client_secret!,
      paymentIntentId: paymentIntent.id,
      amount: totalCents,
      currency: 'usd',
    };
  }

  /**
   * Confirm a PaymentIntent using an Apple Pay token and create the order.
   */
  async confirmApplePayPayment(
    paymentIntentId: string,
    applePayToken: string,
    userId: string,
  ): Promise<IStoreOrder> {
    // Create a PaymentMethod from the Apple Pay token
    const paymentMethod = await stripe.paymentMethods.create({
      type: 'card',
      card: {
        token: applePayToken,
      },
    });

    // Confirm the PaymentIntent with the Apple Pay payment method
    const confirmedIntent = await stripe.paymentIntents.confirm(
      paymentIntentId,
      {
        payment_method: paymentMethod.id,
      },
    );

    if (
      confirmedIntent.status !== 'succeeded' &&
      confirmedIntent.status !== 'requires_capture'
    ) {
      throw new PaymentError(
        `Payment confirmation failed with status: ${confirmedIntent.status}`,
        'PAYMENT_FAILED',
      );
    }

    return this.finalizeConfirmedIntent(confirmedIntent, userId);
  }

  async finalizeCardPayment(
    paymentIntentId: string,
    userId: string,
  ): Promise<IStoreOrder> {
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    return this.finalizeConfirmedIntent(paymentIntent, userId);
  }

  /**
   * Process a Stripe webhook event.
   *
   * Handles both store-order events (payment_intent.*, charge.refunded) and
   * subscription lifecycle events (customer.subscription.*, invoice.*).
   * Duplicate deliveries are suppressed via a ProcessedWebhookEvent record
   * keyed on event.id with a 7-day TTL.
   */
  async handleWebhookEvent(event: Stripe.Event): Promise<void> {
    // Idempotency — short-circuit on duplicate deliveries.
    try {
      const claimed = await claimWebhookEvent(event);
      if (!claimed) {
        logger.info('Stripe webhook duplicate — skipping', {
          eventId: event.id,
          type: event.type,
        });
        return;
      }
    } catch (err) {
      // If the idempotency store is unavailable we still process the event;
      // duplicate writes are bounded by Stripe's retry window and our
      // individual handlers are written to be idempotent at the Mongo level.
      logger.error('Failed to claim Stripe webhook event — processing anyway', {
        eventId: event.id,
        error: err instanceof Error ? err.message : String(err),
      });
    }

    switch (event.type) {
      case 'payment_intent.succeeded': {
        const paymentIntent = event.data.object as Stripe.PaymentIntent;
        await this.finalizeConfirmedIntent(paymentIntent);
        return;
      }

      case 'payment_intent.payment_failed': {
        const paymentIntent = event.data.object as Stripe.PaymentIntent;
        await StoreOrder.findOneAndUpdate(
          { paymentIntentId: paymentIntent.id },
          { status: 'cancelled' },
        );
        return;
      }

      case 'charge.refunded': {
        const charge = event.data.object as Stripe.Charge;
        const piId = charge.payment_intent;
        if (typeof piId === 'string') {
          await StoreOrder.findOneAndUpdate(
            { paymentIntentId: piId },
            { status: 'refunded' },
          );
        }
        return;
      }

      default:
        break;
    }

    if (isStripeSubscriptionEvent(event.type)) {
      await dispatchStripeSubscriptionEvent(event);
      return;
    }

    // Unhandled event type -- ignore silently. We've already recorded it in
    // ProcessedWebhookEvent so Stripe retries remain idempotent.
  }

  /**
   * Get or create a Stripe customer for the user.
   *
   * Resolution order:
   *   1. If `user.stripeCustomerId` is persisted, retrieve it from Stripe.
   *      If Stripe replies with `resource_missing` (customer was deleted),
   *      fall through to create a fresh one and re-link.
   *   2. Backfill path for legacy users (no persisted id): look up by email
   *      via `stripe.customers.list` and accept a match only when
   *      `metadata.userId` equals this user's id. This avoids cross-linking
   *      two users who happen to share an email.
   *   3. Create a new Stripe customer with `metadata.userId` set.
   *
   * In every branch that resolves a customer, `user.stripeCustomerId` is
   * persisted so subsequent calls skip the list/create paths entirely.
   */
  async getOrCreateStripeCustomer(
    userId: string,
    email: string,
  ): Promise<string> {
    const user = await User.findById(userId);
    if (!user) {
      throw new PaymentError('User not found', 'USER_NOT_FOUND');
    }

    // 1. Fast path: we already know the Stripe customer id.
    if (user.stripeCustomerId) {
      try {
        const existing = await stripe.customers.retrieve(user.stripeCustomerId);
        if (existing && !(existing as { deleted?: boolean }).deleted) {
          return existing.id;
        }
        // Deleted customer object returned — fall through to recreate.
      } catch (err: unknown) {
        const code = (err as { code?: string }).code;
        const message = (err as { message?: string }).message ?? '';
        const isMissing =
          code === 'resource_missing' || /No such customer/i.test(message);
        if (!isMissing) {
          throw err;
        }
        // Stale id — recreate below.
      }
    }

    // 2. Backfill path: look up by email but only trust it if the Stripe
    //    customer's metadata.userId matches us.
    const existing = await stripe.customers.list({ email, limit: 1 });
    const match = existing.data.find(
      (c: Stripe.Customer | Stripe.DeletedCustomer) =>
        !(c as { deleted?: boolean }).deleted &&
        (c as Stripe.Customer).metadata?.userId === userId,
    );
    if (match) {
      user.stripeCustomerId = match.id;
      await user.save();
      return match.id;
    }

    // 3. Nothing usable — create a new customer and persist the link.
    const customer = await stripe.customers.create({
      email,
      metadata: { userId },
    });

    user.stripeCustomerId = customer.id;
    await user.save();
    return customer.id;
  }

  /**
   * Look up an existing Stripe customer by email without creating one.
   * Used by the Customer Portal flow to surface a clear 404 for users who
   * have never transacted via Stripe (e.g. Apple-only subscribers).
   */
  async findStripeCustomerByEmail(email: string): Promise<string | null> {
    const existing = await stripe.customers.list({ email, limit: 1 });
    return existing.data.length > 0 ? existing.data[0].id : null;
  }

  /**
   * Create a Stripe Billing Portal session so the user can self-serve
   * subscription management (invoices, payment method, cancel / resume).
   */
  async createBillingPortalSession(
    customerId: string,
    returnUrl: string,
  ): Promise<{ url: string }> {
    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: returnUrl,
    });
    return { url: session.url };
  }

  /**
   * List saved payment methods for a user.
   */
  async getPaymentMethods(
    userId: string,
    email: string,
  ): Promise<Stripe.PaymentMethod[]> {
    const customerId = await this.getOrCreateStripeCustomer(userId, email);

    const methods = await stripe.paymentMethods.list({
      customer: customerId,
      type: 'card',
    });

    return methods.data;
  }

  /**
   * Construct and verify a Stripe webhook event from the raw body and signature.
   */
  constructWebhookEvent(
    rawBody: Buffer,
    signature: string,
  ): Stripe.Event {
    return stripe.webhooks.constructEvent(
      rawBody,
      signature,
      config.stripeWebhookSecret,
    );
  }

  /**
   * Flag a Stripe subscription to cancel at the end of the current period.
   * Throws a PaymentError on upstream Stripe failure so the caller can
   * refuse to mutate local state (truth must not be rewritten on a
   * failed upstream cancel).
   */
  async cancelStripeSubscriptionAtPeriodEnd(
    stripeSubscriptionId: string,
  ): Promise<Stripe.Subscription> {
    if (!stripeSubscriptionId) {
      throw new PaymentError(
        'Missing Stripe subscription id',
        'STRIPE_SUB_ID_MISSING',
      );
    }

    try {
      return await stripe.subscriptions.update(stripeSubscriptionId, {
        cancel_at_period_end: true,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown Stripe error';
      throw new PaymentError(
        `Stripe cancel failed: ${message}`,
        'STRIPE_CANCEL_FAILED',
      );
    }
  }

  private async finalizeConfirmedIntent(
    paymentIntent: Stripe.PaymentIntent,
    userIdOverride?: string,
  ): Promise<IStoreOrder> {
    if (
      paymentIntent.status !== 'succeeded' &&
      paymentIntent.status !== 'requires_capture'
    ) {
      throw new PaymentError(
        `Payment is not finalized (status: ${paymentIntent.status})`,
        'PAYMENT_NOT_FINALIZED',
      );
    }

    const userId = userIdOverride ?? paymentIntent.metadata.userId;
    const cartId = paymentIntent.metadata.cartId;

    if (!userId || !cartId) {
      throw new PaymentError(
        'Missing cartId or userId in payment intent metadata',
        'INVALID_METADATA',
      );
    }

    if (userIdOverride && paymentIntent.metadata.userId && paymentIntent.metadata.userId !== userIdOverride) {
      throw new PaymentError(
        'Payment intent does not belong to the authenticated user',
        'PAYMENT_OWNER_MISMATCH',
      );
    }

    let order = (await StoreOrder.findOne({
      paymentIntentId: paymentIntent.id,
    })) as IStoreOrder | null;

    if (!order) {
      const cart = await StoreCart.findOne({
        _id: new Types.ObjectId(cartId),
        userId: new Types.ObjectId(userId),
      });

      if (!cart || cart.items.length === 0) {
        throw new PaymentError(
          'Order snapshot could not be reconstructed from cart',
          'ORDER_SNAPSHOT_MISSING',
        );
      }

      const subtotalCents = Math.round(cart.subtotal * 100);
      const taxCents = Math.round(subtotalCents * TAX_RATE);
      const totalCents = subtotalCents + taxCents + FLAT_SHIPPING;

      order = await this.upsertPendingOrderFromCart({
        userId,
        cart,
        paymentIntentId: paymentIntent.id,
        shippingAddress: {
          line1: paymentIntent.shipping?.address?.line1 ?? '',
          line2: paymentIntent.shipping?.address?.line2 ?? undefined,
          city: paymentIntent.shipping?.address?.city ?? '',
          state: paymentIntent.shipping?.address?.state ?? '',
          postalCode: paymentIntent.shipping?.address?.postal_code ?? '',
          country: paymentIntent.shipping?.address?.country ?? 'US',
        },
        subtotalCents,
        taxCents,
        shippingCents: FLAT_SHIPPING,
        totalCents,
      });
    }

    if (!order) {
      throw new PaymentError(
        'Order could not be finalized from the confirmed payment',
        'ORDER_FINALIZATION_FAILED',
      );
    }

    if (order.status !== 'paid') {
      order.status = 'paid';
      await order.save();
    }

    await StoreCart.findOneAndUpdate(
      {
        _id: new Types.ObjectId(cartId),
        userId: new Types.ObjectId(userId),
      },
      { items: [], subtotal: 0 },
    );

    return order;
  }

  private async upsertPendingOrderFromCart(params: {
    userId: string;
    cart: InstanceType<typeof StoreCart>;
    paymentIntentId: string;
    shippingAddress: {
      line1: string;
      line2?: string;
      city: string;
      state: string;
      postalCode: string;
      country: string;
    };
    subtotalCents: number;
    taxCents: number;
    shippingCents: number;
    totalCents: number;
  }): Promise<IStoreOrder> {
    const {
      userId,
      cart,
      paymentIntentId,
      shippingAddress,
      subtotalCents,
      taxCents,
      shippingCents,
      totalCents,
    } = params;

    const query = {
      userId: new Types.ObjectId(userId),
      sourceCartId: cart._id,
      status: 'pending' as const,
    };

    const payload = {
      sourceCartId: cart._id,
      paymentIntentId,
      items: cart.items.map((item) => ({
        productId: item.productId,
        sku: item.sku,
        name: item.name,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        lineTotal: item.lineTotal,
      })),
      subtotal: subtotalCents / 100,
      tax: taxCents / 100,
      shipping: shippingCents / 100,
      total: totalCents / 100,
      currency: cart.currency,
      shippingAddress,
    };

    const existing = (await StoreOrder.findOne(query).sort({
      createdAt: -1,
    })) as IStoreOrder | null;
    if (existing) {
      existing.paymentIntentId = paymentIntentId;
      existing.items = payload.items;
      existing.subtotal = payload.subtotal;
      existing.tax = payload.tax;
      existing.shipping = payload.shipping;
      existing.total = payload.total;
      existing.currency = payload.currency;
      existing.shippingAddress = payload.shippingAddress;
      await existing.save();
      return existing as IStoreOrder;
    }

    return (await StoreOrder.create({
      userId: new Types.ObjectId(userId),
      orderNumber: await this.generateOrderNumber(),
      status: 'pending',
      ...payload,
    })) as IStoreOrder;
  }

  private async generateOrderNumber(): Promise<string> {
    const count = await StoreOrder.countDocuments();
    const seq = (count + 1).toString().padStart(6, '0');
    return `GS-${seq}`;
  }
}

export class PaymentError extends Error {
  code: string;

  constructor(message: string, code: string) {
    super(message);
    this.name = 'PaymentError';
    this.code = code;
  }
}
