import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

// ─── Schemas ──────────────────────────────────────────────────────────────────

const scheduleLabSchema = z.object({
  date: z.string().datetime(),
  paymentToken: z.string().min(1),
  productId: z.string().min(1),
});

// ─── Lab Providers (placeholder — replace with real provider data) ────────────

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

// ─── Handlers ─────────────────────────────────────────────────────────────────

async function handleScheduleLab(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const { date, paymentToken: _paymentToken, productId } = req.body as z.infer<typeof scheduleLabSchema>;

    if (productId !== BLOODWORK_PRODUCT.id) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid product', `Product ${productId} not found`);
      return;
    }

    // TODO: Process payment token with Stripe/payment processor
    // For now, accept the token and create the appointment

    // Assign a provider (round-robin for now)
    const provider = LAB_PROVIDERS[Math.floor(Math.random() * LAB_PROVIDERS.length)];

    const appointmentId = `lab-${Date.now()}-${user.sub.slice(-6)}`;

    // TODO: Persist appointment to database
    // TODO: Send confirmation email/notification

    successResponse(
      res,
      {
        appointmentId,
        location: `${provider.name} — ${provider.address}`,
        date,
        status: 'confirmed',
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

async function handleGetBloodworkProduct(_req: Request, res: Response) {
  successResponse(res, BLOODWORK_PRODUCT);
}

// ─── Routes ──────────────────────────────────────────────────────────────────

router.get('/product', isAuthenticated, handleGetBloodworkProduct);
router.post('/schedule', isAuthenticated, validateBody(scheduleLabSchema), handleScheduleLab);

export default router;
