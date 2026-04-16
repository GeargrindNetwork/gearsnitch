import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { LabAppointment } from '../../models/LabAppointment.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

// ─── Schemas ──────────────────────────────────────────────────────────────────

const scheduleLabSchema = z.object({
  date: z.string().datetime(),
  paymentToken: z.string().min(1),
  productId: z.string().min(1),
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

// ─── Handlers ─────────────────────────────────────────────────────────────────

// GET /labs/product
async function handleGetBloodworkProduct(_req: Request, res: Response) {
  successResponse(res, BLOODWORK_PRODUCT);
}

// POST /labs/schedule
async function handleScheduleLab(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const { date, paymentToken: _paymentToken, productId } = req.body as z.infer<typeof scheduleLabSchema>;

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
router.get('/appointments', isAuthenticated, handleListAppointments);
router.patch('/appointments/:id/cancel', isAuthenticated, handleCancelAppointment);

export default router;
