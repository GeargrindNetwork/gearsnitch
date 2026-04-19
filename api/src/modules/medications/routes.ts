import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import {
  MedicationDose,
  type MedicationDoseCategory,
  type MedicationDoseSource,
} from '../../models/MedicationDose.js';
import {
  dateKeyFromDate,
  dayOfYearFromDateKey,
  emptyMedicationOverlay,
  normalizeDoseToMg,
  summarizeMedicationDoses,
} from './utils.js';

const router = Router();

const medicationDoseCategorySchema = z.enum([
  'steroid',
  'peptide',
  'oralMedication',
]);
const medicationDoseUnitSchema = z.enum(['mg', 'mcg', 'iu', 'ml', 'units']);
const medicationDoseSourceSchema = z.enum(['manual', 'ios', 'web', 'imported']);
const medicationDateKeySchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD');

const medicationDoseAmountSchema = z.object({
  value: z.number().finite().min(0),
  unit: medicationDoseUnitSchema,
});

const appleHealthDoseIdSchema = z
  .string()
  .trim()
  .min(1)
  .max(128)
  .nullable()
  .optional();

const createMedicationDoseSchema = z.object({
  cycleId: z.string().min(1).nullable().optional(),
  dateKey: medicationDateKeySchema.optional(),
  category: medicationDoseCategorySchema,
  compoundName: z.string().trim().min(1).max(120),
  dose: medicationDoseAmountSchema,
  occurredAt: z.string().datetime(),
  notes: z.union([z.string().trim().max(4000), z.null()]).optional().default(null),
  source: medicationDoseSourceSchema.optional().default('manual'),
  appleHealthDoseId: appleHealthDoseIdSchema,
});

const updateMedicationDoseSchema = z
  .object({
    cycleId: z.string().min(1).nullable().optional(),
    dateKey: medicationDateKeySchema.optional(),
    category: medicationDoseCategorySchema.optional(),
    compoundName: z.string().trim().min(1).max(120).optional(),
    dose: medicationDoseAmountSchema.optional(),
    occurredAt: z.string().datetime().optional(),
    notes: z.union([z.string().trim().max(4000), z.null()]).optional(),
    source: medicationDoseSourceSchema.optional(),
    appleHealthDoseId: appleHealthDoseIdSchema,
  })
  .refine((value) => Object.keys(value).length > 0, {
    message: 'At least one field must be provided',
  });

type CreateMedicationDoseBody = z.infer<typeof createMedicationDoseSchema>;
type UpdateMedicationDoseBody = z.infer<typeof updateMedicationDoseSchema>;
type MedicationDoseRecord = {
  _id: Types.ObjectId | string;
  userId: Types.ObjectId | string;
  cycleId?: Types.ObjectId | string | null;
  dateKey: string;
  dayOfYear: number;
  category: MedicationDoseCategory;
  compoundName: string;
  dose: {
    value: number;
    unit: string;
  };
  doseMg?: number | null;
  occurredAt: Date | string;
  notes?: string | null;
  source: MedicationDoseSource;
  appleHealthDoseId?: string | null;
  createdAt?: Date | string;
  updatedAt?: Date | string;
};

function parseObjectId(value?: string | null): Types.ObjectId | null {
  if (!value || !Types.ObjectId.isValid(value)) {
    return null;
  }
  return new Types.ObjectId(value);
}

function firstParam(value?: string | string[]): string | null {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }
  return value ?? null;
}

function monthRange(year: number, month: number): { start: Date; end: Date } {
  const start = new Date(Date.UTC(year, month - 1, 1));
  const end = new Date(Date.UTC(year, month, 1));
  return { start, end };
}

function yearRange(year: number): { start: Date; end: Date; daysInYear: number } {
  const start = new Date(Date.UTC(year, 0, 1));
  const end = new Date(Date.UTC(year + 1, 0, 1));
  const daysInYear = Math.round((end.getTime() - start.getTime()) / 86_400_000);
  return { start, end, daysInYear };
}

function toIsoString(value: Date | string | undefined): string | undefined {
  if (value instanceof Date) {
    return value.toISOString();
  }
  return value;
}

function serializeMedicationDose(dose: MedicationDoseRecord) {
  return {
    _id: String(dose._id),
    userId: String(dose.userId),
    cycleId: dose.cycleId ? String(dose.cycleId) : null,
    dateKey: dose.dateKey,
    dayOfYear: dose.dayOfYear,
    category: dose.category,
    compoundName: dose.compoundName,
    dose: {
      value: dose.dose.value,
      unit: dose.dose.unit,
    },
    doseMg: typeof dose.doseMg === 'number' ? dose.doseMg : null,
    occurredAt: toIsoString(dose.occurredAt),
    notes: dose.notes ?? null,
    source: dose.source,
    appleHealthDoseId: dose.appleHealthDoseId ?? null,
    createdAt: toIsoString(dose.createdAt),
    updatedAt: toIsoString(dose.updatedAt),
  };
}

function buildPersistedMedicationDose(
  userId: Types.ObjectId,
  body: CreateMedicationDoseBody,
) {
  const occurredAt = new Date(body.occurredAt);
  const resolvedDateKey = body.dateKey ?? dateKeyFromDate(occurredAt);

  return {
    userId,
    cycleId: parseObjectId(body.cycleId),
    dateKey: resolvedDateKey,
    dayOfYear: dayOfYearFromDateKey(resolvedDateKey),
    category: body.category,
    compoundName: body.compoundName,
    dose: body.dose,
    doseMg: normalizeDoseToMg(body.dose.value, body.dose.unit),
    occurredAt,
    notes: body.notes ?? null,
    source: body.source ?? 'manual',
    appleHealthDoseId: body.appleHealthDoseId ?? null,
  };
}

function buildMedicationDosePatch(body: UpdateMedicationDoseBody) {
  const patch: Record<string, unknown> = {};

  if ('cycleId' in body) {
    patch.cycleId = parseObjectId(body.cycleId ?? null);
  }
  if (body.category) {
    patch.category = body.category;
  }
  if (body.compoundName) {
    patch.compoundName = body.compoundName;
  }
  if (body.notes !== undefined) {
    patch.notes = body.notes ?? null;
  }
  if (body.source) {
    patch.source = body.source;
  }
  if (body.occurredAt) {
    const occurredAt = new Date(body.occurredAt);
    patch.occurredAt = occurredAt;
    if (!body.dateKey) {
      patch.dateKey = dateKeyFromDate(occurredAt);
      patch.dayOfYear = dayOfYearFromDateKey(String(patch.dateKey));
    }
  }
  if (body.dateKey) {
    patch.dateKey = body.dateKey;
    patch.dayOfYear = dayOfYearFromDateKey(body.dateKey);
  }
  if (body.dose) {
    patch.dose = body.dose;
    patch.doseMg = normalizeDoseToMg(body.dose.value, body.dose.unit);
  }
  if ('appleHealthDoseId' in body) {
    patch.appleHealthDoseId = body.appleHealthDoseId ?? null;
  }

  return patch;
}

router.get('/doses', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);
    const page = Math.max(parseInt((req.query.page as string) || '1', 10), 1);
    const limit = Math.min(
      Math.max(parseInt((req.query.limit as string) || '50', 10), 1),
      200,
    );
    const category = req.query.category as MedicationDoseCategory | undefined;
    const from = req.query.from as string | undefined;
    const to = req.query.to as string | undefined;

    const query: Record<string, unknown> = { userId };
    if (category) {
      query.category = category;
    }
    if (from || to) {
      query.dateKey = {};
      if (from) {
        (query.dateKey as Record<string, string>).$gte = from;
      }
      if (to) {
        (query.dateKey as Record<string, string>).$lte = to;
      }
    }

    const [doses, total] = await Promise.all([
      MedicationDose.find(query)
        .sort({ occurredAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit)
        .lean(),
      MedicationDose.countDocuments(query),
    ]);

    successResponse(
      res,
      { doses: doses.map(serializeMedicationDose) },
      StatusCodes.OK,
      {
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      },
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list medication doses',
      (err as Error).message,
    );
  }
});

router.post(
  '/doses',
  isAuthenticated,
  validateBody(createMedicationDoseSchema),
  async (req: Request, res: Response) => {
    try {
      const user = req.user as JwtPayload;
      const userId = new Types.ObjectId(user.sub);
      const body = req.body as CreateMedicationDoseBody;

      // HealthKit dedupe: if this dose carries an appleHealthDoseId we have
      // already ingested for this user (e.g. the iOS app pulled it from
      // HealthKit on a later foreground sync after also pushing it on local
      // log), return the existing row instead of inserting a duplicate. The
      // sparse unique compound index `{userId, appleHealthDoseId}` would
      // otherwise reject on E11000 — handle it explicitly so the client can
      // treat the call as idempotent.
      if (body.appleHealthDoseId) {
        const existing = await MedicationDose.findOne({
          userId,
          appleHealthDoseId: body.appleHealthDoseId,
        }).lean();
        if (existing) {
          successResponse(res, { dose: serializeMedicationDose(existing) }, StatusCodes.OK);
          return;
        }
      }

      const dose = await MedicationDose.create(buildPersistedMedicationDose(userId, body));
      successResponse(res, { dose: serializeMedicationDose(dose) }, StatusCodes.CREATED);
    } catch (err) {
      // Race-window guard: another concurrent POST may have inserted the same
      // appleHealthDoseId between the findOne and the create. Mongo throws
      // E11000 — treat as a successful idempotent retry.
      if ((err as { code?: number }).code === 11000) {
        const userIdObj = new Types.ObjectId((req.user as JwtPayload).sub);
        const body = req.body as CreateMedicationDoseBody;
        if (body.appleHealthDoseId) {
          const existing = await MedicationDose.findOne({
            userId: userIdObj,
            appleHealthDoseId: body.appleHealthDoseId,
          }).lean();
          if (existing) {
            successResponse(res, { dose: serializeMedicationDose(existing) }, StatusCodes.OK);
            return;
          }
        }
      }
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to create medication dose',
        (err as Error).message,
      );
    }
  },
);

router.patch(
  '/doses/:doseId',
  isAuthenticated,
  validateBody(updateMedicationDoseSchema),
  async (req: Request, res: Response) => {
    try {
      const user = req.user as JwtPayload;
      const userId = new Types.ObjectId(user.sub);
      const doseId = parseObjectId(firstParam(req.params.doseId));

      if (!doseId) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Valid doseId is required');
        return;
      }

      const patch = buildMedicationDosePatch(req.body as UpdateMedicationDoseBody);
      const dose = await MedicationDose.findOneAndUpdate(
        { _id: doseId, userId },
        { $set: patch },
        { new: true },
      ).lean();

      if (!dose) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Medication dose not found');
        return;
      }

      successResponse(res, { dose: serializeMedicationDose(dose) });
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update medication dose',
        (err as Error).message,
      );
    }
  },
);

router.delete('/doses/:doseId', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);
    const doseId = parseObjectId(firstParam(req.params.doseId));

    if (!doseId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Valid doseId is required');
      return;
    }

    const deleted = await MedicationDose.findOneAndDelete({ _id: doseId, userId }).lean();
    if (!deleted) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Medication dose not found');
      return;
    }

    successResponse(res, { doseId: String(doseId), deleted: true });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to delete medication dose',
      (err as Error).message,
    );
  }
});

router.get('/day/:date', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);
    const date = firstParam(req.params.date);

    if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Date must be YYYY-MM-DD format');
      return;
    }

    const doses = await MedicationDose.find({ userId, dateKey: date })
      .sort({ occurredAt: 1 })
      .lean();

    successResponse(res, {
      dateKey: date,
      doses: doses.map(serializeMedicationDose),
      totals: summarizeMedicationDoses(doses),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load medication day',
      (err as Error).message,
    );
  }
});

router.get('/month', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);
    const year = parseInt(req.query.year as string, 10);
    const month = parseInt(req.query.month as string, 10);

    if (!year || !month || month < 1 || month > 12) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Valid year and month (1-12) are required');
      return;
    }

    const { start, end } = monthRange(year, month);
    const startKey = dateKeyFromDate(start);
    const endKey = dateKeyFromDate(end);

    const doses = await MedicationDose.find({
      userId,
      dateKey: { $gte: startKey, $lt: endKey },
    }).lean();

    const days: Record<string, ReturnType<typeof emptyMedicationOverlay>> = {};
    const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
    for (let day = 1; day <= daysInMonth; day += 1) {
      const key = dateKeyFromDate(new Date(Date.UTC(year, month - 1, day)));
      days[key] = emptyMedicationOverlay();
    }

    const byDay = new Map<string, typeof doses>();
    for (const dose of doses) {
      const current = byDay.get(dose.dateKey) ?? [];
      current.push(dose);
      byDay.set(dose.dateKey, current);
    }

    for (const [key, dayDoses] of byDay.entries()) {
      days[key] = summarizeMedicationDoses(dayDoses);
    }

    successResponse(res, {
      year,
      month,
      days,
      totals: summarizeMedicationDoses(doses),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load medication month',
      (err as Error).message,
    );
  }
});

router.get('/graph/year', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const userId = new Types.ObjectId(user.sub);
    const year = parseInt(req.query.year as string, 10);

    if (!year) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Valid year is required');
      return;
    }

    const { start, end, daysInYear } = yearRange(year);
    const startKey = dateKeyFromDate(start);
    const endKey = dateKeyFromDate(end);

    const doses = await MedicationDose.find({
      userId,
      dateKey: { $gte: startKey, $lt: endKey },
    }).lean();

    const steroidMgByDay = Array.from({ length: daysInYear }, () => 0);
    const peptideMgByDay = Array.from({ length: daysInYear }, () => 0);
    const oralMedicationMgByDay = Array.from({ length: daysInYear }, () => 0);

    for (const dose of doses) {
      if (typeof dose.doseMg !== 'number' || dose.doseMg < 0) {
        continue;
      }

      const index = dose.dayOfYear - 1;
      if (index < 0 || index >= daysInYear) {
        continue;
      }

      if (dose.category === 'steroid') {
        steroidMgByDay[index] += dose.doseMg;
      } else if (dose.category === 'peptide') {
        peptideMgByDay[index] += dose.doseMg;
      } else if (dose.category === 'oralMedication') {
        oralMedicationMgByDay[index] += dose.doseMg;
      }
    }

    const totals = summarizeMedicationDoses(doses);

    successResponse(res, {
      year,
      axis: {
        x: { startDay: 1, endDay: daysInYear },
        yMg: { min: 0, max: 20 },
      },
      series: {
        steroidMgByDay,
        peptideMgByDay,
        oralMedicationMgByDay,
      },
      totalsMg: {
        steroid: totals.categoryDoseMg.steroid,
        peptide: totals.categoryDoseMg.peptide,
        oralMedication: totals.categoryDoseMg.oralMedication,
        all: totals.totalDoseMg,
      },
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load medication year graph',
      (err as Error).message,
    );
  }
});

export default router;
