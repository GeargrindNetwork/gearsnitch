import StripeLib from 'stripe';
import { Stripe } from 'stripe/cjs/stripe.core.js';
import { Types } from 'mongoose';
import config from '../config/index.js';
import { StoreCart } from '../models/StoreCart.js';
import { StoreOrder, type IStoreOrder } from '../models/StoreOrder.js';
import { User } from '../models/User.js';

const TAX_RATE = 0.0825; // 8.25%
const FLAT_SHIPPING = 599; // $5.99 in cents

const stripe = new StripeLib(config.stripeSecretKey);

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

    const cartId = confirmedIntent.metadata.cartId;
    if (!cartId) {
      throw new PaymentError(
        'Missing cartId in payment intent metadata',
        'INVALID_METADATA',
      );
    }

    // Create the order from the cart
    const { OrderService } = await import('./OrderService.js');
    const orderService = new OrderService();
    const order = await orderService.createFromCart(
      userId,
      cartId,
      paymentIntentId,
      {
        line1: confirmedIntent.shipping?.address?.line1 ?? '',
        line2: confirmedIntent.shipping?.address?.line2 ?? undefined,
        city: confirmedIntent.shipping?.address?.city ?? '',
        state: confirmedIntent.shipping?.address?.state ?? '',
        postalCode: confirmedIntent.shipping?.address?.postal_code ?? '',
        country: confirmedIntent.shipping?.address?.country ?? '',
      },
    );

    // Mark order as paid since payment succeeded
    order.status = 'paid';
    await order.save();

    return order;
  }

  /**
   * Process a Stripe webhook event.
   */
  async handleWebhookEvent(event: Stripe.Event): Promise<void> {
    switch (event.type) {
      case 'payment_intent.succeeded': {
        const paymentIntent = event.data.object as Stripe.PaymentIntent;
        await StoreOrder.findOneAndUpdate(
          { paymentIntentId: paymentIntent.id },
          { status: 'paid' },
        );
        break;
      }

      case 'payment_intent.payment_failed': {
        const paymentIntent = event.data.object as Stripe.PaymentIntent;
        await StoreOrder.findOneAndUpdate(
          { paymentIntentId: paymentIntent.id },
          { status: 'cancelled' },
        );
        break;
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
        break;
      }

      default:
        // Unhandled event type -- ignore silently
        break;
    }
  }

  /**
   * Get or create a Stripe customer for the user.
   */
  async getOrCreateStripeCustomer(
    userId: string,
    email: string,
  ): Promise<string> {
    // Search for existing customer by metadata
    const existing = await stripe.customers.list({
      email,
      limit: 1,
    });

    if (existing.data.length > 0) {
      return existing.data[0].id;
    }

    const customer = await stripe.customers.create({
      email,
      metadata: { userId },
    });

    return customer.id;
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
}

export class PaymentError extends Error {
  code: string;

  constructor(message: string, code: string) {
    super(message);
    this.name = 'PaymentError';
    this.code = code;
  }
}
