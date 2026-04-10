import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { DosingHistory } from '../../models/DosingHistory.js';

const router = Router();

// ---------------------------------------------------------------------------
// Preset Substances
// ---------------------------------------------------------------------------

const PRESET_SUBSTANCES = [
  { name: 'Testosterone Cypionate', defaultConcentrationMgMl: 200 },
  { name: 'Testosterone Enanthate', defaultConcentrationMgMl: 250 },
  { name: 'Testosterone Propionate', defaultConcentrationMgMl: 100 },
  { name: 'Nandrolone Decanoate', defaultConcentrationMgMl: 200 },
  { name: 'Trenbolone Acetate', defaultConcentrationMgMl: 100 },
  { name: 'Trenbolone Enanthate', defaultConcentrationMgMl: 200 },
  { name: 'Boldenone Undecylenate', defaultConcentrationMgMl: 300 },
  { name: 'Masteron (Drostanolone)', defaultConcentrationMgMl: 100 },
  { name: 'Primobolan (Methenolone)', defaultConcentrationMgMl: 100 },
  { name: 'HCG', defaultConcentrationMgMl: 5000, unit: 'IU/mL', requiresReconstitution: true },
  { name: 'BPC-157', defaultConcentrationMgMl: 5, requiresReconstitution: true },
  { name: 'TB-500', defaultConcentrationMgMl: 5, requiresReconstitution: true },
  { name: 'Semaglutide', defaultConcentrationMgMl: 2.5, requiresReconstitution: true },
  { name: 'Tirzepatide', defaultConcentrationMgMl: 5, requiresReconstitution: true },
  { name: 'MK-677 (Ibutamoren)', defaultConcentrationMgMl: 25 },
];

// ---------------------------------------------------------------------------
// Validation Schemas
// ---------------------------------------------------------------------------

const calculateSchema = z.object({
  concentration: z.number().positive('Concentration must be positive'),
  desiredDose: z.number().positive('Desired dose must be positive'),
  reconstitutionVolume: z.number().positive().optional(),
});

const saveHistorySchema = z.object({
  substance: z.string().min(1, 'Substance is required'),
  concentration: z.number().positive(),
  desiredDose: z.number().positive(),
  volumeInjected: z.number().positive(),
  reconstitutionVolume: z.number().positive().nullable().optional(),
  notes: z.string().nullable().optional(),
});

// ---------------------------------------------------------------------------
// POST /dosing/calculate — Stateless dose calculation
// ---------------------------------------------------------------------------

router.post(
  '/calculate',
  isAuthenticated,
  validateBody(calculateSchema),
  async (req: Request, res: Response) => {
    try {
      const { concentration, desiredDose, reconstitutionVolume } =
        req.body as z.infer<typeof calculateSchema>;

      // If reconstitution is involved, recalculate effective concentration
      // effectiveConc = totalMg / reconstitutionVolume
      // For standard vials: concentration is already mg/mL
      const effectiveConc = reconstitutionVolume
        ? concentration / reconstitutionVolume
        : concentration;

      const volumeMl = desiredDose / effectiveConc;
      // Standard insulin syringe: 1 mL = 100 units
      const syringeUnits = Math.round(volumeMl * 100 * 10) / 10;

      const warnings: string[] = [];

      if (volumeMl > 3) {
        warnings.push('Volume exceeds 3 mL — consider splitting injection across two sites');
      }
      if (volumeMl < 0.05) {
        warnings.push('Very small volume — verify concentration and dose');
      }
      if (syringeUnits > 100) {
        warnings.push('Exceeds standard insulin syringe capacity (100 units / 1 mL)');
      }

      successResponse(res, {
        volumeMl: Math.round(volumeMl * 1000) / 1000,
        syringeUnits,
        effectiveConcentration: Math.round(effectiveConc * 1000) / 1000,
        warnings,
      });
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Calculation failed',
        (err as Error).message,
      );
    }
  },
);

// ---------------------------------------------------------------------------
// POST /dosing/history — Save dose to history
// ---------------------------------------------------------------------------

router.post(
  '/history',
  isAuthenticated,
  validateBody(saveHistorySchema),
  async (req: Request, res: Response) => {
    try {
      const user = req.user as JwtPayload;
      const body = req.body as z.infer<typeof saveHistorySchema>;

      const entry = await DosingHistory.create({
        userId: new Types.ObjectId(user.sub),
        substance: body.substance,
        concentration: body.concentration,
        desiredDose: body.desiredDose,
        volumeInjected: body.volumeInjected,
        reconstitutionVolume: body.reconstitutionVolume ?? null,
        notes: body.notes ?? null,
      });

      successResponse(res, entry, StatusCodes.CREATED);
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to save dose history',
        (err as Error).message,
      );
    }
  },
);

// ---------------------------------------------------------------------------
// GET /dosing/history — Get dose history
// ---------------------------------------------------------------------------

router.get('/history', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string) || 20));
    const skip = (page - 1) * limit;

    const filter = { userId: new Types.ObjectId(user.sub) };

    const [history, total] = await Promise.all([
      DosingHistory.find(filter).sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
      DosingHistory.countDocuments(filter),
    ]);

    successResponse(res, history, StatusCodes.OK, {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load dose history',
      (err as Error).message,
    );
  }
});

// ---------------------------------------------------------------------------
// GET /dosing/substances — Get preset substances list
// ---------------------------------------------------------------------------

router.get('/substances', isAuthenticated, (_req: Request, res: Response) => {
  successResponse(res, PRESET_SUBSTANCES);
});

export default router;
