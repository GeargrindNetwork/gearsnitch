import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { Cycle } from '../../models/Cycle.js';
import { CycleEntry } from '../../models/CycleEntry.js';

const router = Router();

const cycleStatusSchema = z.enum(['planned', 'active', 'paused', 'completed', 'archived']);
const cycleTypeSchema = z.enum(['peptide', 'steroid', 'mixed', 'other']);
const cycleCompoundCategorySchema = z.enum(['peptide', 'steroid', 'support', 'pct', 'other']);
const cycleDoseUnitSchema = z.enum(['mg', 'mcg', 'iu', 'ml', 'units']);
const cycleRouteSchema = z.enum(['injection', 'oral', 'topical', 'other']);
const cycleEntrySourceSchema = z.enum(['manual', 'ios', 'web', 'imported']);

const cycleCompoundPlanSchema = z.object({
  compoundName: z.string().trim().min(1).max(120),
  compoundCategory: cycleCompoundCategorySchema.optional().default('other'),
  targetDose: z.number().finite().min(0).nullable().optional().default(null),
  doseUnit: cycleDoseUnitSchema.optional().default('mg'),
  route: cycleRouteSchema.nullable().optional().default(null),
});

const createCycleSchema = z.object({
  name: z.string().trim().min(1).max(120),
  type: cycleTypeSchema.optional().default('other'),
  status: cycleStatusSchema.optional().default('planned'),
  startDate: z.string().datetime(),
  endDate: z.union([z.string().datetime(), z.null()]).optional().default(null),
  timezone: z.string().trim().min(1).max(80).optional().default('UTC'),
  notes: z.union([z.string().trim().max(4000), z.null()]).optional().default(null),
  tags: z.array(z.string().trim().min(1).max(64)).optional().default([]),
  compounds: z.array(cycleCompoundPlanSchema).optional().default([]),
}).superRefine((value, ctx) => {
  if (value.endDate && new Date(value.endDate) < new Date(value.startDate)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['endDate'],
      message: 'endDate must be greater than or equal to startDate',
    });
  }
});

const updateCycleSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  type: cycleTypeSchema.optional(),
  status: cycleStatusSchema.optional(),
  startDate: z.string().datetime().optional(),
  endDate: z.union([z.string().datetime(), z.null()]).optional(),
  timezone: z.string().trim().min(1).max(80).optional(),
  notes: z.union([z.string().trim().max(4000), z.null()]).optional(),
  tags: z.array(z.string().trim().min(1).max(64)).optional(),
  compounds: z.array(cycleCompoundPlanSchema).optional(),
});

const createCycleEntrySchema = z.object({
  compoundName: z.string().trim().min(1).max(120),
  compoundCategory: cycleCompoundCategorySchema.optional().default('other'),
  route: cycleRouteSchema.optional().default('other'),
  occurredAt: z.string().datetime().optional(),
  plannedDose: z.number().finite().min(0).nullable().optional().default(null),
  actualDose: z.number().finite().min(0).nullable().optional().default(null),
  doseUnit: cycleDoseUnitSchema.optional().default('mg'),
  notes: z.union([z.string().trim().max(4000), z.null()]).optional().default(null),
  source: cycleEntrySourceSchema.optional().default('manual'),
}).superRefine((value, ctx) => {
  if (value.plannedDose === null && value.actualDose === null) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['actualDose'],
      message: 'Either plannedDose or actualDose is required',
    });
  }
});

const updateCycleEntrySchema = z.object({
  compoundName: z.string().trim().min(1).max(120).optional(),
  compoundCategory: cycleCompoundCategorySchema.optional(),
  route: cycleRouteSchema.optional(),
  occurredAt: z.string().datetime().optional(),
  plannedDose: z.number().finite().min(0).nullable().optional(),
  actualDose: z.number().finite().min(0).nullable().optional(),
  doseUnit: cycleDoseUnitSchema.optional(),
  notes: z.union([z.string().trim().max(4000), z.null()]).optional(),
  source: cycleEntrySourceSchema.optional(),
}).refine((value) => Object.keys(value).length > 0, {
  message: 'At least one field must be provided',
});

type CreateCycleBody = z.infer<typeof createCycleSchema>;
type UpdateCycleBody = z.infer<typeof updateCycleSchema>;
type CreateCycleEntryBody = z.infer<typeof createCycleEntrySchema>;
type UpdateCycleEntryBody = z.infer<typeof updateCycleEntrySchema>;

interface PopulatedCycleRef {
  _id: Types.ObjectId | string;
  name: string;
  status: string;
  type: string;
  startDate: Date | string;
  endDate: Date | string | null;
  timezone?: string;
}

function parseObjectId(value: string): Types.ObjectId | null {
  return Types.ObjectId.isValid(value) ? new Types.ObjectId(value) : null;
}

function dateKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function dateKeyInTimezone(date: Date, timezone: string): string {
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    const parts = formatter.formatToParts(date);
    const year = parts.find((part) => part.type === 'year')?.value;
    const month = parts.find((part) => part.type === 'month')?.value;
    const day = parts.find((part) => part.type === 'day')?.value;

    if (year && month && day) {
      return `${year}-${month}-${day}`;
    }
  } catch {
    // fall through to UTC fallback
  }
  return dateKey(date);
}

function parseDateParam(value: string): Date | null {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed;
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function cycleOverlapsYear(cycle: Record<string, any>, year: number): boolean {
  const yearStart = new Date(Date.UTC(year, 0, 1));
  const yearEnd = new Date(Date.UTC(year + 1, 0, 1));
  const startDate = cycle.startDate instanceof Date ? cycle.startDate : new Date(cycle.startDate);
  const endDate = cycle.endDate
    ? cycle.endDate instanceof Date
      ? cycle.endDate
      : new Date(cycle.endDate)
    : null;

  if (startDate >= yearEnd) {
    return false;
  }
  if (endDate && endDate < yearStart) {
    return false;
  }
  return true;
}

function cycleActiveOnDate(cycle: Record<string, any>, dayKey: string): boolean {
  const timezone = typeof cycle.timezone === 'string' ? cycle.timezone : 'UTC';
  const startKey = dateKeyInTimezone(
    cycle.startDate instanceof Date ? cycle.startDate : new Date(cycle.startDate),
    timezone,
  );
  const endKey = cycle.endDate
    ? dateKeyInTimezone(
        cycle.endDate instanceof Date ? cycle.endDate : new Date(cycle.endDate),
        timezone,
      )
    : null;
  return startKey <= dayKey && (!endKey || endKey >= dayKey);
}

function isPopulatedCycleRef(value: unknown): value is PopulatedCycleRef {
  return (
    typeof value === 'object'
    && value !== null
    && '_id' in value
    && 'name' in value
    && 'status' in value
    && 'type' in value
    && 'startDate' in value
    && 'endDate' in value
  );
}

function serializeCycle(cycle: Record<string, any>) {
  return {
    _id: String(cycle._id),
    userId: String(cycle.userId),
    name: cycle.name,
    type: cycle.type,
    status: cycle.status,
    startDate: cycle.startDate,
    endDate: cycle.endDate,
    timezone: cycle.timezone,
    notes: cycle.notes ?? null,
    tags: Array.isArray(cycle.tags) ? cycle.tags : [],
    compounds: Array.isArray(cycle.compounds)
      ? cycle.compounds.map((compound: Record<string, any>) => ({
          compoundName: compound.compoundName,
          compoundCategory: compound.compoundCategory ?? 'other',
          targetDose: typeof compound.targetDose === 'number' ? compound.targetDose : null,
          doseUnit: compound.doseUnit ?? 'mg',
          route: compound.route ?? null,
        }))
      : [],
    createdAt: cycle.createdAt,
    updatedAt: cycle.updatedAt,
  };
}

function serializeCycleEntry(entry: Record<string, any>) {
  const cycleRef = entry.cycleId;
  const cycleDetails =
    cycleRef && typeof cycleRef === 'object' && '_id' in cycleRef
      ? {
          _id: String(cycleRef._id),
          name: cycleRef.name,
          status: cycleRef.status,
          type: cycleRef.type,
          startDate: cycleRef.startDate,
          endDate: cycleRef.endDate,
          timezone: cycleRef.timezone,
        }
      : null;

  return {
    _id: String(entry._id),
    userId: String(entry.userId),
    cycleId: cycleDetails ? cycleDetails._id : String(entry.cycleId),
    cycle: cycleDetails,
    compoundName: entry.compoundName,
    compoundCategory: entry.compoundCategory,
    route: entry.route,
    occurredAt: entry.occurredAt,
    dateKey: entry.dateKey,
    plannedDose: typeof entry.plannedDose === 'number' ? entry.plannedDose : null,
    actualDose: typeof entry.actualDose === 'number' ? entry.actualDose : null,
    doseUnit: entry.doseUnit,
    notes: entry.notes ?? null,
    source: entry.source,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
  };
}

router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 20));
    const skip = (page - 1) * limit;
    const status = typeof req.query.status === 'string' ? req.query.status : undefined;

    const filter: Record<string, unknown> = { userId };
    if (status) {
      if (!cycleStatusSchema.safeParse(status).success) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycle status filter');
        return;
      }
      filter.status = status;
    }

    const [cycles, total] = await Promise.all([
      Cycle.find(filter).sort({ updatedAt: -1 }).skip(skip).limit(limit).lean(),
      Cycle.countDocuments(filter),
    ]);

    successResponse(
      res,
      cycles.map(serializeCycle),
      StatusCodes.OK,
      {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    );
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list cycles',
      (error as Error).message,
    );
  }
});

router.post(
  '/',
  isAuthenticated,
  validateBody(createCycleSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const body = req.body as CreateCycleBody;

      const cycle = await Cycle.create({
        userId,
        name: body.name,
        type: body.type,
        status: body.status,
        startDate: new Date(body.startDate),
        endDate: body.endDate ? new Date(body.endDate) : null,
        timezone: body.timezone,
        notes: body.notes,
        tags: body.tags,
        compounds: body.compounds,
      });

      successResponse(res, serializeCycle(cycle.toObject()), StatusCodes.CREATED);
    } catch (error) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to create cycle',
        (error as Error).message,
      );
    }
  },
);

router.get('/day/:date', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const date = req.params.date as string;

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Date must be YYYY-MM-DD format');
      return;
    }

    const cycleId = typeof req.query.cycleId === 'string' ? parseObjectId(req.query.cycleId) : null;
    if (typeof req.query.cycleId === 'string' && !cycleId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycleId query parameter');
      return;
    }

    const filter: Record<string, unknown> = { userId, dateKey: date };
    if (cycleId) {
      filter.cycleId = cycleId;
    }

    const entries = await CycleEntry.find(filter)
      .sort({ occurredAt: -1 })
      .populate({
        path: 'cycleId',
        select: 'name status type startDate endDate timezone',
      })
      .lean();

    const byCompound = new Map<string, {
      compoundName: string;
      compoundCategory: string;
      doseUnit: string;
      count: number;
      totalPlannedDose: number;
      totalActualDose: number;
    }>();
    const byCycle = new Map<string, {
      cycleId: string;
      cycleName: string;
      cycleStatus: string;
      entryCount: number;
    }>();
    const cycleStatusSnapshot = new Map<string, {
      cycleId: string;
      name: string;
      status: string;
      type: string;
      startDate: Date;
      endDate: Date | null;
      timezone: string;
    }>();

    for (const entry of entries) {
      const compoundKey = `${entry.compoundName}::${entry.compoundCategory}::${entry.doseUnit}`;
      const existingCompound = byCompound.get(compoundKey) ?? {
        compoundName: entry.compoundName,
        compoundCategory: entry.compoundCategory,
        doseUnit: entry.doseUnit,
        count: 0,
        totalPlannedDose: 0,
        totalActualDose: 0,
      };
      existingCompound.count += 1;
      existingCompound.totalPlannedDose += typeof entry.plannedDose === 'number' ? entry.plannedDose : 0;
      existingCompound.totalActualDose += typeof entry.actualDose === 'number' ? entry.actualDose : 0;
      byCompound.set(compoundKey, existingCompound);

      const rawCycle = entry.cycleId as PopulatedCycleRef | Types.ObjectId;
      const populatedCycle = isPopulatedCycleRef(rawCycle) ? rawCycle : null;
      const resolvedCycleId = populatedCycle ? String(populatedCycle._id) : String(rawCycle);
      const existingCycle = byCycle.get(resolvedCycleId) ?? {
        cycleId: resolvedCycleId,
        cycleName:
          populatedCycle
            ? String(populatedCycle.name)
            : 'Unknown cycle',
        cycleStatus:
          populatedCycle
            ? String(populatedCycle.status)
            : 'unknown',
        entryCount: 0,
      };
      existingCycle.entryCount += 1;
      byCycle.set(resolvedCycleId, existingCycle);

      if (populatedCycle) {
        cycleStatusSnapshot.set(resolvedCycleId, {
          cycleId: resolvedCycleId,
          name: String(populatedCycle.name),
          status: String(populatedCycle.status),
          type: String(populatedCycle.type),
          startDate:
            populatedCycle.startDate instanceof Date
              ? populatedCycle.startDate
              : new Date(populatedCycle.startDate),
          endDate: populatedCycle.endDate
            ? populatedCycle.endDate instanceof Date
              ? populatedCycle.endDate
              : new Date(populatedCycle.endDate)
            : null,
          timezone: typeof populatedCycle.timezone === 'string' ? populatedCycle.timezone : 'UTC',
        });
      }
    }

    successResponse(res, {
      date,
      entries: entries.map(serializeCycleEntry),
      totals: {
        entryCount: entries.length,
        byCompound: [...byCompound.values()],
        byCycle: [...byCycle.values()],
      },
      cycleStatusSnapshot: [...cycleStatusSnapshot.values()],
    });
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load cycle day summary',
      (error as Error).message,
    );
  }
});

router.get('/month', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const year = parseInt(req.query.year as string, 10);
    const month = parseInt(req.query.month as string, 10);

    if (!year || !month || month < 1 || month > 12) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Valid year and month (1-12) are required');
      return;
    }

    const cycleId = typeof req.query.cycleId === 'string' ? parseObjectId(req.query.cycleId) : null;
    if (typeof req.query.cycleId === 'string' && !cycleId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycleId query parameter');
      return;
    }

    const start = new Date(Date.UTC(year, month - 1, 1));
    const end = new Date(Date.UTC(year, month, 1));
    const startKey = dateKey(start);
    const endKey = dateKey(end);
    const dayCount = daysInMonth(year, month);

    const entryFilter: Record<string, unknown> = {
      userId,
      dateKey: { $gte: startKey, $lt: endKey },
    };
    if (cycleId) {
      entryFilter.cycleId = cycleId;
    }

    const [entries, activeCycles] = await Promise.all([
      CycleEntry.find(entryFilter).lean(),
      Cycle.find({
        userId,
        ...(cycleId ? { _id: cycleId } : {}),
        startDate: { $lt: end },
        $or: [{ endDate: null }, { endDate: { $gte: start } }],
      })
        .select('_id startDate endDate status name type timezone')
        .lean(),
    ]);

    const days = Array.from({ length: dayCount }, (_, index) => {
      const current = new Date(Date.UTC(year, month - 1, index + 1));
      const key = dateKey(current);
      return {
        date: key,
        entryCount: 0,
        totalPlannedDose: 0,
        totalActualDose: 0,
        activeCycleCount: 0,
      };
    });
    const dayIndexByDate = new Map(days.map((day, index) => [day.date, index]));

    for (const entry of entries) {
      const index = dayIndexByDate.get(entry.dateKey);
      if (index === undefined) {
        continue;
      }

      days[index].entryCount += 1;
      days[index].totalPlannedDose += typeof entry.plannedDose === 'number' ? entry.plannedDose : 0;
      days[index].totalActualDose += typeof entry.actualDose === 'number' ? entry.actualDose : 0;
    }

    for (const day of days) {
      day.activeCycleCount = activeCycles.reduce(
        (count, cycle) => (cycleActiveOnDate(cycle, day.date) ? count + 1 : count),
        0,
      );
    }

    const totals = days.reduce(
      (accumulator, day) => {
        accumulator.entryCount += day.entryCount;
        accumulator.totalPlannedDose += day.totalPlannedDose;
        accumulator.totalActualDose += day.totalActualDose;
        if (day.entryCount > 0) {
          accumulator.activeDays += 1;
        }
        return accumulator;
      },
      {
        entryCount: 0,
        totalPlannedDose: 0,
        totalActualDose: 0,
        activeDays: 0,
        activeCycleCount: activeCycles.length,
      },
    );

    successResponse(res, {
      year,
      month,
      days,
      totals,
    });
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load cycle month summary',
      (error as Error).message,
    );
  }
});

router.get('/year', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const year = parseInt(req.query.year as string, 10);

    if (!year) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Valid year is required');
      return;
    }

    const cycleId = typeof req.query.cycleId === 'string' ? parseObjectId(req.query.cycleId) : null;
    if (typeof req.query.cycleId === 'string' && !cycleId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycleId query parameter');
      return;
    }

    const yearStart = new Date(Date.UTC(year, 0, 1));
    const yearEnd = new Date(Date.UTC(year + 1, 0, 1));
    const startKey = dateKey(yearStart);
    const endKey = dateKey(yearEnd);

    const entryFilter: Record<string, unknown> = {
      userId,
      dateKey: { $gte: startKey, $lt: endKey },
    };
    if (cycleId) {
      entryFilter.cycleId = cycleId;
    }

    const cycleFilter: Record<string, unknown> = {
      userId,
      ...(cycleId ? { _id: cycleId } : {}),
      startDate: { $lt: yearEnd },
      $or: [{ endDate: null }, { endDate: { $gte: yearStart } }],
    };

    const [entries, cycles] = await Promise.all([
      CycleEntry.find(entryFilter).lean(),
      Cycle.find(cycleFilter)
        .select('_id name type status startDate endDate timezone')
        .lean(),
    ]);

    const monthlyBuckets = Array.from({ length: 12 }, (_, index) => ({
      month: index + 1,
      entryCount: 0,
      activeDays: 0,
      totalPlannedDose: 0,
      totalActualDose: 0,
      cycleStarts: 0,
      cycleEnds: 0,
      topCompounds: [] as Array<{
        compoundName: string;
        compoundCategory: string;
        doseUnit: string;
        count: number;
        totalActualDose: number;
      }>,
    }));

    const monthActiveDays = Array.from({ length: 12 }, () => new Set<string>());
    const monthCompoundMaps = Array.from(
      { length: 12 },
      () =>
        new Map<string, {
          compoundName: string;
          compoundCategory: string;
          doseUnit: string;
          count: number;
          totalActualDose: number;
        }>(),
    );
    const yearCompoundMap = new Map<string, {
      compoundName: string;
      compoundCategory: string;
      doseUnit: string;
      count: number;
      totalActualDose: number;
    }>();
    const yearActiveDays = new Set<string>();

    for (const entry of entries) {
      const entryMonth = parseInt(entry.dateKey.slice(5, 7), 10) - 1;
      if (entryMonth < 0 || entryMonth > 11) {
        continue;
      }

      monthlyBuckets[entryMonth].entryCount += 1;
      monthlyBuckets[entryMonth].totalPlannedDose += typeof entry.plannedDose === 'number' ? entry.plannedDose : 0;
      monthlyBuckets[entryMonth].totalActualDose += typeof entry.actualDose === 'number' ? entry.actualDose : 0;
      monthActiveDays[entryMonth].add(entry.dateKey);
      yearActiveDays.add(entry.dateKey);

      const compoundKey = `${entry.compoundName}::${entry.compoundCategory}::${entry.doseUnit}`;
      const monthCompound = monthCompoundMaps[entryMonth].get(compoundKey) ?? {
        compoundName: entry.compoundName,
        compoundCategory: entry.compoundCategory,
        doseUnit: entry.doseUnit,
        count: 0,
        totalActualDose: 0,
      };
      monthCompound.count += 1;
      monthCompound.totalActualDose += typeof entry.actualDose === 'number' ? entry.actualDose : 0;
      monthCompoundMaps[entryMonth].set(compoundKey, monthCompound);

      const yearCompound = yearCompoundMap.get(compoundKey) ?? {
        compoundName: entry.compoundName,
        compoundCategory: entry.compoundCategory,
        doseUnit: entry.doseUnit,
        count: 0,
        totalActualDose: 0,
      };
      yearCompound.count += 1;
      yearCompound.totalActualDose += typeof entry.actualDose === 'number' ? entry.actualDose : 0;
      yearCompoundMap.set(compoundKey, yearCompound);
    }

    for (const cycle of cycles) {
      if (!cycleOverlapsYear(cycle, year)) {
        continue;
      }

      const timezone = typeof cycle.timezone === 'string' ? cycle.timezone : 'UTC';
      const startDate = cycle.startDate instanceof Date ? cycle.startDate : new Date(cycle.startDate);
      const startKeyForTimezone = dateKeyInTimezone(startDate, timezone);
      if (startKeyForTimezone.startsWith(`${year}-`)) {
        const startMonth = parseInt(startKeyForTimezone.slice(5, 7), 10) - 1;
        if (startMonth >= 0 && startMonth < 12) {
          monthlyBuckets[startMonth].cycleStarts += 1;
        }
      }

      if (cycle.endDate) {
        const endDate = cycle.endDate instanceof Date ? cycle.endDate : new Date(cycle.endDate);
        const endKeyForTimezone = dateKeyInTimezone(endDate, timezone);
        if (endKeyForTimezone.startsWith(`${year}-`)) {
          const endMonth = parseInt(endKeyForTimezone.slice(5, 7), 10) - 1;
          if (endMonth >= 0 && endMonth < 12) {
            monthlyBuckets[endMonth].cycleEnds += 1;
          }
        }
      }
    }

    for (let index = 0; index < monthlyBuckets.length; index += 1) {
      monthlyBuckets[index].activeDays = monthActiveDays[index].size;
      monthlyBuckets[index].topCompounds = [...monthCompoundMaps[index].values()]
        .sort((a, b) => {
          if (b.count !== a.count) {
            return b.count - a.count;
          }
          return b.totalActualDose - a.totalActualDose;
        })
        .slice(0, 3);
    }

    const totals = monthlyBuckets.reduce(
      (accumulator, month) => {
        accumulator.entryCount += month.entryCount;
        accumulator.totalPlannedDose += month.totalPlannedDose;
        accumulator.totalActualDose += month.totalActualDose;
        accumulator.cycleStarts += month.cycleStarts;
        accumulator.cycleEnds += month.cycleEnds;
        return accumulator;
      },
      {
        entryCount: 0,
        activeDays: yearActiveDays.size,
        totalPlannedDose: 0,
        totalActualDose: 0,
        cycleStarts: 0,
        cycleEnds: 0,
      },
    );

    const topCompounds = [...yearCompoundMap.values()]
      .sort((a, b) => {
        if (b.count !== a.count) {
          return b.count - a.count;
        }
        return b.totalActualDose - a.totalActualDose;
      })
      .slice(0, 5);

    successResponse(res, {
      year,
      months: monthlyBuckets,
      totals,
      topCompounds,
    });
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load cycle year summary',
      (error as Error).message,
    );
  }
});

router.get('/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const cycleId = parseObjectId(req.params.id as string);

    if (!cycleId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycle ID');
      return;
    }

    const cycle = await Cycle.findOne({ _id: cycleId, userId }).lean();
    if (!cycle) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle not found');
      return;
    }

    successResponse(res, serializeCycle(cycle));
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load cycle',
      (error as Error).message,
    );
  }
});

router.patch(
  '/:id',
  isAuthenticated,
  validateBody(updateCycleSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const cycleId = parseObjectId(req.params.id as string);

      if (!cycleId) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycle ID');
        return;
      }

      const existingCycle = await Cycle.findOne({ _id: cycleId, userId });
      if (!existingCycle) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle not found');
        return;
      }

      const body = req.body as UpdateCycleBody;
      const nextStartDate = body.startDate ? new Date(body.startDate) : existingCycle.startDate;
      const nextEndDate =
        body.endDate !== undefined
          ? body.endDate
            ? new Date(body.endDate)
            : null
          : existingCycle.endDate;

      if (nextEndDate && nextEndDate < nextStartDate) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'endDate must be greater than or equal to startDate');
        return;
      }

      const updatePayload: Record<string, unknown> = {};
      if (body.name !== undefined) updatePayload.name = body.name;
      if (body.type !== undefined) updatePayload.type = body.type;
      if (body.status !== undefined) updatePayload.status = body.status;
      if (body.startDate !== undefined) updatePayload.startDate = nextStartDate;
      if (body.endDate !== undefined) updatePayload.endDate = nextEndDate;
      if (body.timezone !== undefined) updatePayload.timezone = body.timezone;
      if (body.notes !== undefined) updatePayload.notes = body.notes;
      if (body.tags !== undefined) updatePayload.tags = body.tags;
      if (body.compounds !== undefined) updatePayload.compounds = body.compounds;

      const updatedCycle = await Cycle.findOneAndUpdate(
        { _id: cycleId, userId },
        updatePayload,
        { new: true },
      ).lean();

      if (!updatedCycle) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle not found');
        return;
      }

      successResponse(res, serializeCycle(updatedCycle));
    } catch (error) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update cycle',
        (error as Error).message,
      );
    }
  },
);

router.delete('/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const cycleId = parseObjectId(req.params.id as string);

    if (!cycleId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycle ID');
      return;
    }

    const cycle = await Cycle.findOne({ _id: cycleId, userId }).lean();
    if (!cycle) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle not found');
      return;
    }

    const [deleteCycleResult, deleteEntriesResult] = await Promise.all([
      Cycle.deleteOne({ _id: cycleId, userId }),
      CycleEntry.deleteMany({ cycleId, userId }),
    ]);

    if (!deleteCycleResult.deletedCount) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle not found');
      return;
    }

    successResponse(res, {
      deletedCycleId: String(cycleId),
      deletedEntries: deleteEntriesResult.deletedCount ?? 0,
    });
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to delete cycle',
      (error as Error).message,
    );
  }
});

router.get('/:id/entries', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const cycleId = parseObjectId(req.params.id as string);

    if (!cycleId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycle ID');
      return;
    }

    const cycle = await Cycle.findOne({ _id: cycleId, userId }).lean();
    if (!cycle) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle not found');
      return;
    }

    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 20));
    const skip = (page - 1) * limit;
    const fromParam = typeof req.query.from === 'string' ? parseDateParam(req.query.from) : null;
    const toParam = typeof req.query.to === 'string' ? parseDateParam(req.query.to) : null;

    if (req.query.from && !fromParam) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid from date');
      return;
    }
    if (req.query.to && !toParam) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid to date');
      return;
    }

    const filter: Record<string, unknown> = { userId, cycleId };
    if (fromParam || toParam) {
      filter.occurredAt = {
        ...(fromParam ? { $gte: fromParam } : {}),
        ...(toParam ? { $lte: toParam } : {}),
      };
    }

    const [entries, total] = await Promise.all([
      CycleEntry.find(filter).sort({ occurredAt: -1 }).skip(skip).limit(limit).lean(),
      CycleEntry.countDocuments(filter),
    ]);

    successResponse(
      res,
      entries.map(serializeCycleEntry),
      StatusCodes.OK,
      {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    );
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list cycle entries',
      (error as Error).message,
    );
  }
});

router.post(
  '/:id/entries',
  isAuthenticated,
  validateBody(createCycleEntrySchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const cycleId = parseObjectId(req.params.id as string);

      if (!cycleId) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycle ID');
        return;
      }

      const cycle = await Cycle.findOne({ _id: cycleId, userId }).lean();
      if (!cycle) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle not found');
        return;
      }

      const body = req.body as CreateCycleEntryBody;
      const occurredAt = body.occurredAt ? new Date(body.occurredAt) : new Date();
      const cycleTimezone = typeof cycle.timezone === 'string' ? cycle.timezone : 'UTC';

      const entry = await CycleEntry.create({
        userId,
        cycleId,
        compoundName: body.compoundName,
        compoundCategory: body.compoundCategory,
        route: body.route,
        occurredAt,
        dateKey: dateKeyInTimezone(occurredAt, cycleTimezone),
        plannedDose: body.plannedDose,
        actualDose: body.actualDose,
        doseUnit: body.doseUnit,
        notes: body.notes,
        source: body.source,
      });

      successResponse(res, serializeCycleEntry(entry.toObject()), StatusCodes.CREATED);
    } catch (error) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to create cycle entry',
        (error as Error).message,
      );
    }
  },
);

router.patch(
  '/entries/:entryId',
  isAuthenticated,
  validateBody(updateCycleEntrySchema),
  async (req: Request, res: Response) => {
    try {
      const userId = new Types.ObjectId((req.user as JwtPayload).sub);
      const entryId = parseObjectId(req.params.entryId as string);

      if (!entryId) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycle entry ID');
        return;
      }

      const existingEntry = await CycleEntry.findOne({ _id: entryId, userId }).lean();
      if (!existingEntry) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle entry not found');
        return;
      }

      const body = req.body as UpdateCycleEntryBody;
      const updatePayload: Record<string, unknown> = {};

      if (body.compoundName !== undefined) updatePayload.compoundName = body.compoundName;
      if (body.compoundCategory !== undefined) updatePayload.compoundCategory = body.compoundCategory;
      if (body.route !== undefined) updatePayload.route = body.route;
      if (body.plannedDose !== undefined) updatePayload.plannedDose = body.plannedDose;
      if (body.actualDose !== undefined) updatePayload.actualDose = body.actualDose;
      if (body.doseUnit !== undefined) updatePayload.doseUnit = body.doseUnit;
      if (body.notes !== undefined) updatePayload.notes = body.notes;
      if (body.source !== undefined) updatePayload.source = body.source;
      if (body.occurredAt !== undefined) {
        const occurredAt = new Date(body.occurredAt);
        const cycle = await Cycle.findOne({
          _id: existingEntry.cycleId,
          userId,
        })
          .select('timezone')
          .lean();
        const cycleTimezone = typeof cycle?.timezone === 'string' ? cycle.timezone : 'UTC';
        updatePayload.occurredAt = occurredAt;
        updatePayload.dateKey = dateKeyInTimezone(occurredAt, cycleTimezone);
      }

      const nextPlannedDose =
        body.plannedDose !== undefined ? body.plannedDose : existingEntry.plannedDose ?? null;
      const nextActualDose =
        body.actualDose !== undefined ? body.actualDose : existingEntry.actualDose ?? null;
      if (nextPlannedDose === null && nextActualDose === null) {
        errorResponse(res, StatusCodes.BAD_REQUEST, 'Either plannedDose or actualDose is required');
        return;
      }

      const updatedEntry = await CycleEntry.findOneAndUpdate(
        { _id: entryId, userId },
        updatePayload,
        { new: true },
      ).lean();

      if (!updatedEntry) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle entry not found');
        return;
      }

      successResponse(res, serializeCycleEntry(updatedEntry));
    } catch (error) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update cycle entry',
        (error as Error).message,
      );
    }
  },
);

router.delete('/entries/:entryId', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = new Types.ObjectId((req.user as JwtPayload).sub);
    const entryId = parseObjectId(req.params.entryId as string);

    if (!entryId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid cycle entry ID');
      return;
    }

    const entry = await CycleEntry.findOne({ _id: entryId, userId }).lean();
    if (!entry) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Cycle entry not found');
      return;
    }

    await CycleEntry.deleteOne({ _id: entryId, userId });
    successResponse(res, { deletedEntryId: String(entryId) });
  } catch (error) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to delete cycle entry',
      (error as Error).message,
    );
  }
});

export default router;
