import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated } from '../../middleware/auth.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { PaymentService, PaymentError } from '../../services/PaymentService.js';

const router = Router();
const paymentService = new PaymentService();

// --- Zod Schemas ---

const ShippingAddressSchema = z.object({
  line1: z.string().min(1),
  line2: z.string().optional(),
  city: z.string().min(1),
  state: z.string().min(1),
  postalCode: z.string().min(1),
  country: z.string().length(2).default('US'),
});

const CreateIntentSchema = z.object({
  cartId: z.string().min(1),
  shippingAddress: ShippingAddressSchema,
});

const ApplePaySchema = z.object({
  paymentIntentId: z.string().min(1).startsWith('pi_'),
  applePayToken: z.string().min(1),
});

const FinalizePaymentSchema = z.object({
  paymentIntentId: z.string().min(1).startsWith('pi_'),
});

// --- Routes ---

/**
 * POST /payments/create-intent
 * Create a Stripe PaymentIntent from the user's cart.
 */
router.post(
  '/create-intent',
  isAuthenticated,
  async (req: Request, res: Response): Promise<void> => {
    try {
      const parsed = CreateIntentSchema.safeParse(req.body);
      if (!parsed.success) {
        errorResponse(
          res,
          StatusCodes.BAD_REQUEST,
          'Validation failed',
          parsed.error.flatten().fieldErrors,
        );
        return;
      }

      const { cartId, shippingAddress } = parsed.data;
      const userId = req.user!.sub;

      const result = await paymentService.createPaymentIntent(
        userId,
        cartId,
        shippingAddress,
      );

      successResponse(res, result, StatusCodes.CREATED);
    } catch (err) {
      if (err instanceof PaymentError) {
        errorResponse(res, StatusCodes.BAD_REQUEST, err.message);
        return;
      }
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to create payment intent',
      );
    }
  },
);

/**
 * POST /payments/apple-pay
 * Process an Apple Pay token payment.
 */
router.post(
  '/apple-pay',
  isAuthenticated,
  async (req: Request, res: Response): Promise<void> => {
    try {
      const parsed = ApplePaySchema.safeParse(req.body);
      if (!parsed.success) {
        errorResponse(
          res,
          StatusCodes.BAD_REQUEST,
          'Validation failed',
          parsed.error.flatten().fieldErrors,
        );
        return;
      }

      const { paymentIntentId, applePayToken } = parsed.data;
      const userId = req.user!.sub;

      const order = await paymentService.confirmApplePayPayment(
        paymentIntentId,
        applePayToken,
        userId,
      );

      successResponse(res, {
        orderId: order._id.toString(),
        orderNumber: order.orderNumber,
        status: order.status,
        total: order.total,
        currency: order.currency,
      });
    } catch (err) {
      if (err instanceof PaymentError) {
        errorResponse(res, StatusCodes.BAD_REQUEST, err.message);
        return;
      }
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to process Apple Pay payment',
      );
    }
  },
);

/**
 * POST /payments/finalize
 * Finalize a Stripe card payment after client-side confirmation succeeds.
 */
router.post(
  '/finalize',
  isAuthenticated,
  async (req: Request, res: Response): Promise<void> => {
    try {
      const parsed = FinalizePaymentSchema.safeParse(req.body);
      if (!parsed.success) {
        errorResponse(
          res,
          StatusCodes.BAD_REQUEST,
          'Validation failed',
          parsed.error.flatten().fieldErrors,
        );
        return;
      }

      const order = await paymentService.finalizeCardPayment(
        parsed.data.paymentIntentId,
        req.user!.sub,
      );

      successResponse(res, {
        orderId: order._id.toString(),
        orderNumber: order.orderNumber,
        status: order.status,
        total: order.total,
        currency: order.currency,
      });
    } catch (err) {
      if (err instanceof PaymentError) {
        errorResponse(res, StatusCodes.BAD_REQUEST, err.message);
        return;
      }
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to finalize payment',
      );
    }
  },
);

/**
 * POST /payments/webhook
 * Stripe webhook handler. Requires raw body for signature verification.
 */
router.post(
  '/webhook',
  async (req: Request, res: Response): Promise<void> => {
    try {
      const signature = req.headers['stripe-signature'];
      if (!signature || typeof signature !== 'string') {
        errorResponse(
          res,
          StatusCodes.BAD_REQUEST,
          'Missing stripe-signature header',
        );
        return;
      }

      const event = paymentService.constructWebhookEvent(
        req.body as Buffer,
        signature,
      );

      await paymentService.handleWebhookEvent(event);

      successResponse(res, { received: true });
    } catch (err) {
      const message =
        err instanceof Error ? err.message : 'Webhook processing failed';
      errorResponse(res, StatusCodes.BAD_REQUEST, message);
    }
  },
);

/**
 * GET /payments/methods
 * Get saved payment methods for the authenticated user.
 */
router.get(
  '/methods',
  isAuthenticated,
  async (req: Request, res: Response): Promise<void> => {
    try {
      const userId = req.user!.sub;
      const email = req.user!.email;

      const methods = await paymentService.getPaymentMethods(userId, email);

      successResponse(
        res,
        methods.map((m) => ({
          id: m.id,
          brand: m.card?.brand ?? null,
          last4: m.card?.last4 ?? null,
          expMonth: m.card?.exp_month ?? null,
          expYear: m.card?.exp_year ?? null,
          type: m.type,
        })),
      );
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to retrieve payment methods',
      );
    }
  },
);

export default router;
