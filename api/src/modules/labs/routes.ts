import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { labAuditMiddleware } from '../../middleware/labAudit.js';
import { LabAppointment } from '../../models/LabAppointment.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import logger from '../../utils/logger.js';
import {
  labProviderFactory,
  NotImplementedError,
  type LabProvider,
  type LabCollectionMethod,
} from './providers/index.js';

const router = Router();

// Every /labs/* request gets an audit log entry before any handler runs.
router.use(labAuditMiddleware);

// ─── Schemas ──────────────────────────────────────────────────────────────────

const scheduleLabSchema = z.object({
  date: z.string().datetime(),
  paymentToken: z.string().min(1),
  productId: z.string().min(1),
});

const collectionMethodSchema = z.enum(['phlebotomy_site', 'mobile_phleb', 'self_collect']);

const createOrderSchema = z.object({
  testIds: z.array(z.string().min(1)).min(1),
  collectionMethod: collectionMethodSchema,
  drawSiteId: z.string().optional(),
  preferredDateTime: z.string().datetime().optional(),
  /**
   * @phi — patient identity. Accepted here but never logged by
   *        `labAuditMiddleware`; providers forward to the vendor under BAA.
   */
  patient: z.object({
    firstName: z.string().min(1),
    lastName: z.string().min(1),
    dateOfBirth: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    sexAtBirth: z.enum(['male', 'female', 'unknown']),
    email: z.string().email(),
    phone: z.string().min(3),
    address: z.object({
      line1: z.string().min(1),
      line2: z.string().optional(),
      city: z.string().min(1),
      state: z.string().length(2),
      postalCode: z.string().min(3),
    }),
  }),
});

const drawSiteQuerySchema = z.object({
  zip: z.string().regex(/^\d{5}(-\d{4})?$/),
  radius: z.coerce.number().int().positive().max(250).optional(),
});

// ─── Lab Providers (legacy list, retained for existing schedule flow) ────────

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
 * Translates provider-side errors into safe client responses without
 * leaking stack traces or vendor internals (both PHI-adjacent and
 * vendor-confidential). Details are written to the server log only.
 */
function sendProviderError(
  res: Response,
  provider: LabProvider,
  route: string,
  err: unknown,
): void {
  const error = err as Error;
  const isNotImplemented = error instanceof NotImplementedError;
  logger.warn('lab provider error', {
    provider: provider.id,
    route,
    message: error.message,
    kind: isNotImplemented ? 'not_implemented' : 'provider_error',
  });

  if (isNotImplemented) {
    errorResponse(
      res,
      StatusCodes.NOT_IMPLEMENTED,
      'Lab provider integration pending',
    );
    return;
  }

  errorResponse(
    res,
    StatusCodes.BAD_GATEWAY,
    'Lab provider error',
  );
}

// ─── Handlers (legacy) ────────────────────────────────────────────────────────

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

// ─── Handlers (provider-backed) ──────────────────────────────────────────────

// GET /labs/tests
async function handleListTests(_req: Request, res: Response) {
  const provider = labProviderFactory();
  try {
    const tests = await provider.listTests();
    successResponse(res, { provider: provider.id, tests });
  } catch (err) {
    sendProviderError(res, provider, 'listTests', err);
  }
}

// GET /labs/draw-sites?zip=12345&radius=25
async function handleListDrawSites(req: Request, res: Response) {
  const provider = labProviderFactory();
  const parsed = drawSiteQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid draw-site query', parsed.error.flatten());
    return;
  }

  try {
    const sites = await provider.listDrawSites({
      zip: parsed.data.zip,
      radius: parsed.data.radius,
    });
    successResponse(res, { provider: provider.id, sites });
  } catch (err) {
    sendProviderError(res, provider, 'listDrawSites', err);
  }
}

// POST /labs/orders
async function handleCreateOrder(req: Request, res: Response) {
  const provider = labProviderFactory();
  const body = req.body as z.infer<typeof createOrderSchema>;
  const user = req.user as JwtPayload;

  try {
    const order = await provider.createOrder({
      testIds: body.testIds,
      collectionMethod: body.collectionMethod as LabCollectionMethod,
      drawSiteId: body.drawSiteId,
      preferredDateTime: body.preferredDateTime,
      patient: {
        userId: user.sub,
        ...body.patient,
      },
    });
    successResponse(res, { provider: provider.id, order }, StatusCodes.CREATED);
  } catch (err) {
    sendProviderError(res, provider, 'createOrder', err);
  }
}

function extractOrderId(req: Request): string {
  const raw = (req.params as Record<string, string | string[] | undefined>).orderId;
  return Array.isArray(raw) ? (raw[0] ?? '') : (raw ?? '');
}

// GET /labs/orders/:orderId
async function handleGetOrderStatus(req: Request, res: Response) {
  const provider = labProviderFactory();
  const orderId = extractOrderId(req);

  try {
    const status = await provider.getOrderStatus(orderId);
    successResponse(res, { provider: provider.id, status });
  } catch (err) {
    sendProviderError(res, provider, 'getOrderStatus', err);
  }
}

// GET /labs/orders/:orderId/results
async function handleGetOrderResults(req: Request, res: Response) {
  const provider = labProviderFactory();
  const orderId = extractOrderId(req);

  try {
    const report = await provider.getResults(orderId);
    // NOTE: `report` is a FHIR DiagnosticReport and is PHI. We do not log
    // it and we do not include error `details` in non-dev responses.
    successResponse(res, { provider: provider.id, report });
  } catch (err) {
    sendProviderError(res, provider, 'getResults', err);
  }
}

// POST /labs/orders/:orderId/cancel
async function handleCancelOrder(req: Request, res: Response) {
  const provider = labProviderFactory();
  const orderId = extractOrderId(req);

  try {
    const status = await provider.cancelOrder(orderId);
    successResponse(res, { provider: provider.id, status });
  } catch (err) {
    sendProviderError(res, provider, 'cancelOrder', err);
  }
}

// ─── Routes ──────────────────────────────────────────────────────────────────

// Legacy surface — preserved so existing iOS builds keep working during rollout.
router.get('/product', isAuthenticated, handleGetBloodworkProduct);
router.post('/schedule', isAuthenticated, validateBody(scheduleLabSchema), handleScheduleLab);
router.get('/appointments', isAuthenticated, handleListAppointments);
router.patch('/appointments/:id/cancel', isAuthenticated, handleCancelAppointment);

// Provider-backed surface — LabProvider factory delegates.
router.get('/tests', isAuthenticated, handleListTests);
router.get('/draw-sites', isAuthenticated, handleListDrawSites);
router.post('/orders', isAuthenticated, validateBody(createOrderSchema), handleCreateOrder);
router.get('/orders/:orderId', isAuthenticated, handleGetOrderStatus);
router.get('/orders/:orderId/results', isAuthenticated, handleGetOrderResults);
router.post('/orders/:orderId/cancel', isAuthenticated, handleCancelOrder);

export default router;
