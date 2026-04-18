import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { LabAppointment } from '../../models/LabAppointment.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import {
  isRestricted,
  LAB_STATE_RESTRICTED_ERROR_CODE,
  stateRestrictedMessage,
} from './stateEligibility.js';

const router = Router();

// ─── Schemas ──────────────────────────────────────────────────────────────────

/**
 * Shipping address schema for lab orders. The `state` field is gated by
 * `isRestricted` before any provider/Stripe/Mongo side-effects (mirrors iOS
 * PR #27).
 */
const shippingAddressSchema = z.object({
  name: z.string().min(1).optional(),
  line1: z.string().min(1).optional(),
  line2: z.string().optional(),
  city: z.string().min(1).optional(),
  state: z.string().min(2).max(2),
  postalCode: z.string().min(1).optional(),
  country: z.string().optional(),
});

const scheduleLabSchema = z.object({
  date: z.string().datetime(),
  paymentToken: z.string().min(1),
  productId: z.string().min(1),
  shippingAddress: shippingAddressSchema.optional(),
});

const orderLabSchema = z.object({
  productId: z.string().min(1),
  paymentToken: z.string().min(1),
  shippingAddress: shippingAddressSchema,
});

// ─── Lab Providers ────────────────────────────────────────────────────────────

const LAB_PROVIDERS = [
  { id: 'quest-001', name: 'Quest Diagnostics', address: 'Nearest available location' },
  { id: 'labcorp-001', name: 'Labcorp', address: 'Nearest available location' },
];

const BLOODWORK_PRODUCT = {
  id: 'com.gearsnitch.app.bloodwork',
  name: 'Comprehensive Blood Work Panel',
  price: 69.99,
  currency: 'USD',
  includes: [
    'Complete Blood Count (CBC)',
    'Comprehensive Metabolic Panel (CMP)',
    'Lipid Panel',
    'Testosterone (Total & Free)',
    'Thyroid Panel (TSH, T3, T4)',
    'Liver Function (AST, ALT)',
    'Kidney Function (BUN, Creatinine)',
    'Hemoglobin A1C',
  ],
};

function serializeAppointment(appt: Record<string, any>) {
  return {
    _id: String(appt._id),
    appointmentDate: appt.appointmentDate?.toISOString?.() ?? appt.appointmentDate,
    location: appt.location,
    provider: appt.provider,
    status: appt.status,
    productId: appt.productId,
    amountCharged: appt.amountCharged,
    createdAt: appt.createdAt?.toISOString?.() ?? appt.createdAt,
  };
}

/**
 * Writes the canonical state-eligibility rejection response.
 *
 * Uses a raw JSON body (not the standard envelope) so iOS + backend speak the
 * exact shape PR #27 keys off of:
 *   { error: 'LAB_NOT_AVAILABLE_IN_STATE', state: '<XX>', message: '<copy>' }
 *
 * The audit middleware from PR #26 observes the 400 status and logs the
 * rejection automatically — no extra instrumentation needed here.
 */
function sendStateRestrictedResponse(res: Response, stateCode: string): void {
  const normalized = String(stateCode).trim().toUpperCase();
  res.status(StatusCodes.BAD_REQUEST).json({
    error: LAB_STATE_RESTRICTED_ERROR_CODE,
    state: normalized,
    message: stateRestrictedMessage(normalized),
  });
}

// ─── Handlers ─────────────────────────────────────────────────────────────────

// GET /labs/product
async function handleGetBloodworkProduct(_req: Request, res: Response) {
  successResponse(res, BLOODWORK_PRODUCT);
}

// POST /labs/schedule
async function handleScheduleLab(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const {
      date,
      paymentToken: _paymentToken,
      productId,
      shippingAddress,
    } = req.body as z.infer<typeof scheduleLabSchema>;

    // State-eligibility gate (Rupa Health: NY/NJ/RI restricted). Must fire
    // BEFORE product lookup, Stripe charge, or Mongo write. Mirrors iOS PR #27.
    const shippingState = shippingAddress?.state;
    if (isRestricted(shippingState)) {
      sendStateRestrictedResponse(res, shippingState as string);
      return;
    }

    if (productId !== BLOODWORK_PRODUCT.id) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid product', `Product ${productId} not found`);
      return;
    }

    // TODO: Process payment token with Stripe
    const paymentId = `pay_${Date.now()}`;

    // Assign a provider
    const provider = LAB_PROVIDERS[Math.floor(Math.random() * LAB_PROVIDERS.length)];

    const appointment = await LabAppointment.create({
      userId: new Types.ObjectId(user.sub),
      productId,
      appointmentDate: new Date(date),
      location: `${provider.name} — ${provider.address}`,
      provider: provider.name,
      status: 'confirmed',
      amountCharged: BLOODWORK_PRODUCT.price,
      paymentId,
    });

    successResponse(
      res,
      {
        appointmentId: String(appointment._id),
        location: appointment.location,
        date: appointment.appointmentDate.toISOString(),
        status: appointment.status,
        product: BLOODWORK_PRODUCT.name,
        amountCharged: BLOODWORK_PRODUCT.price,
      },
      StatusCodes.CREATED,
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to schedule lab appointment',
      (err as Error).message,
    );
  }
}

// POST /labs/orders — at-home lab order placement (Rupa-backed).
// Gates on state eligibility BEFORE any provider call, Stripe charge, or
// LabOrder row. Paired with iOS PR #27 client-side gate.
async function handlePlaceLabOrder(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const { productId, shippingAddress } = req.body as z.infer<typeof orderLabSchema>;

    // State-eligibility gate. Must run BEFORE any side-effect.
    if (isRestricted(shippingAddress.state)) {
      sendStateRestrictedResponse(res, shippingAddress.state);
      return;
    }

    if (productId !== BLOODWORK_PRODUCT.id) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid product', `Product ${productId} not found`);
      return;
    }

    // NOTE: LabProvider + LabOrder persistence land in a follow-up PR. For now,
    // this endpoint only shapes the guard and response envelope. Returning 501
    // signals to callers that the post-gate flow is intentionally incomplete.
    void user;
    errorResponse(
      res,
      StatusCodes.NOT_IMPLEMENTED,
      'Lab order placement not yet implemented',
      'POST /labs/orders is scaffolded with the state-eligibility gate; provider integration lands in a follow-up.',
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to place lab order',
      (err as Error).message,
    );
  }
}

// GET /labs/appointments
async function handleListAppointments(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const appointments = await LabAppointment.find({
      userId: new Types.ObjectId(user.sub),
    })
      .sort({ appointmentDate: -1 })
      .limit(20)
      .lean();

    successResponse(res, appointments.map(serializeAppointment));
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load appointments', (err as Error).message);
  }
}

// PATCH /labs/appointments/:id/cancel
async function handleCancelAppointment(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const appointmentId = req.params.id;

    const appointment = await LabAppointment.findOneAndUpdate(
      {
        _id: appointmentId,
        userId: new Types.ObjectId(user.sub),
        status: 'confirmed',
      },
      { $set: { status: 'cancelled' } },
      { new: true }
    ).lean();

    if (!appointment) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Appointment not found or already completed/cancelled');
      return;
    }

    // TODO: Process refund via Stripe

    successResponse(res, serializeAppointment(appointment));
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to cancel appointment', (err as Error).message);
  }
}

// ─── Routes ──────────────────────────────────────────────────────────────────

router.get('/product', isAuthenticated, handleGetBloodworkProduct);
router.post('/schedule', isAuthenticated, validateBody(scheduleLabSchema), handleScheduleLab);
router.post('/orders', isAuthenticated, validateBody(orderLabSchema), handlePlaceLabOrder);
router.get('/appointments', isAuthenticated, handleListAppointments);
router.patch('/appointments/:id/cancel', isAuthenticated, handleCancelAppointment);

export default router;
