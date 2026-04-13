import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { Meal } from '../../models/Meal.js';
import { WaterLog } from '../../models/WaterLog.js';
import { NutritionGoal } from '../../models/NutritionGoal.js';
import { User } from '../../models/User.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

const DEFAULT_TARGETS = {
  dailyCalorieTarget: 2000,
  proteinTargetG: 150,
  carbsTargetG: 250,
  fatTargetG: 65,
  fiberTargetG: 30,
  waterTargetMl: 3000,
};

const dateKeyPattern = /^\d{4}-\d{2}-\d{2}$/;

const logMealSchema = z.object({
  date: z.string().regex(dateKeyPattern, 'Date must be YYYY-MM-DD').optional(),
  mealType: z.enum(['breakfast', 'lunch', 'dinner', 'snack']),
  name: z.string().trim().min(1).max(200),
  calories: z.number().finite().min(0),
  protein: z.number().finite().min(0).optional(),
  carbs: z.number().finite().min(0).optional(),
  fat: z.number().finite().min(0).optional(),
  fiber: z.number().finite().min(0).optional(),
  sugar: z.number().finite().min(0).optional(),
});

const logWaterSchema = z.object({
  date: z.string().regex(dateKeyPattern, 'Date must be YYYY-MM-DD').optional(),
  amountMl: z.number().finite().min(1).max(10000),
  loggedAt: z.string().datetime().optional(),
});

type NutritionPreferenceSnapshot = {
  calorieTarget?: string;
  proteinTarget?: string;
  carbsTarget?: string;
  fatTarget?: string;
  fiberTarget?: string;
  waterTargetMl?: string;
};

class CaloriesValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CaloriesValidationError';
  }
}

function todayDateKey(): string {
  return new Date().toISOString().slice(0, 10);
}

function resolveDateKey(value: unknown): string {
  if (typeof value === 'undefined') {
    return todayDateKey();
  }

  if (typeof value === 'string' && dateKeyPattern.test(value)) {
    return value;
  }

  throw new CaloriesValidationError(`Invalid date value: ${String(value)}`);
}

function parseNumericTarget(value: unknown, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return fallback;
  }
  return parsed;
}

function serializeMeal(meal: Record<string, any>) {
  return {
    _id: String(meal._id),
    name: meal.name,
    calories: meal.calories ?? 0,
    protein: meal.protein ?? null,
    carbs: meal.carbs ?? null,
    fat: meal.fat ?? null,
    fiber: meal.fiber ?? null,
    sugar: meal.sugar ?? null,
    mealType: meal.mealType,
    createdAt: meal.createdAt,
  };
}

function deriveTargets(
  nutritionGoal: Record<string, any> | null,
  customPreferences: NutritionPreferenceSnapshot,
) {
  if (nutritionGoal) {
    return {
      dailyCalorieTarget: nutritionGoal.dailyCalorieTarget,
      proteinTargetG: nutritionGoal.proteinTargetG,
      carbsTargetG: nutritionGoal.carbsTargetG,
      fatTargetG: nutritionGoal.fatTargetG,
      fiberTargetG: nutritionGoal.fiberTargetG,
      waterTargetMl: nutritionGoal.waterTargetMl,
    };
  }

  return {
    dailyCalorieTarget: parseNumericTarget(
      customPreferences.calorieTarget,
      DEFAULT_TARGETS.dailyCalorieTarget,
    ),
    proteinTargetG: parseNumericTarget(
      customPreferences.proteinTarget,
      DEFAULT_TARGETS.proteinTargetG,
    ),
    carbsTargetG: parseNumericTarget(
      customPreferences.carbsTarget,
      DEFAULT_TARGETS.carbsTargetG,
    ),
    fatTargetG: parseNumericTarget(
      customPreferences.fatTarget,
      DEFAULT_TARGETS.fatTargetG,
    ),
    fiberTargetG: parseNumericTarget(
      customPreferences.fiberTarget,
      DEFAULT_TARGETS.fiberTargetG,
    ),
    waterTargetMl: parseNumericTarget(
      customPreferences.waterTargetMl,
      DEFAULT_TARGETS.waterTargetMl,
    ),
  };
}

async function buildDailySummary(userId: string, date: string) {
  const userObjectId = new Types.ObjectId(userId);
  const [meals, waterLogs, nutritionGoal, user] = await Promise.all([
    Meal.find({ userId: userObjectId, date }).sort({ createdAt: -1 }).lean(),
    WaterLog.find({ userId: userObjectId, date }).sort({ loggedAt: -1, createdAt: -1 }).lean(),
    NutritionGoal.findOne({ userId: userObjectId }).lean(),
    User.findById(userObjectId).select('preferences').lean(),
  ]);

  const customPreferences = (
    user
    && typeof user.preferences === 'object'
    && user.preferences !== null
    && 'custom' in user.preferences
    && typeof user.preferences.custom === 'object'
    && user.preferences.custom !== null
      ? user.preferences.custom
      : {}
  ) as NutritionPreferenceSnapshot;

  const targets = deriveTargets(nutritionGoal, customPreferences);

  const mealTotals = meals.reduce(
    (totals, meal) => ({
      totalCalories: totals.totalCalories + (meal.calories ?? 0),
      protein: totals.protein + (meal.protein ?? 0),
      carbs: totals.carbs + (meal.carbs ?? 0),
      fat: totals.fat + (meal.fat ?? 0),
      fiber: totals.fiber + (meal.fiber ?? 0),
      sugar: totals.sugar + (meal.sugar ?? 0),
    }),
    {
      totalCalories: 0,
      protein: 0,
      carbs: 0,
      fat: 0,
      fiber: 0,
      sugar: 0,
    },
  );

  const waterMl = waterLogs.reduce((sum, log) => sum + (log.amountMl ?? 0), 0);

  return {
    date,
    totalCalories: mealTotals.totalCalories,
    targetCalories: targets.dailyCalorieTarget,
    protein: mealTotals.protein,
    carbs: mealTotals.carbs,
    fat: mealTotals.fat,
    fiber: mealTotals.fiber,
    sugar: mealTotals.sugar,
    waterMl,
    waterTargetMl: targets.waterTargetMl,
    meals: meals.map(serializeMeal),
  };
}

async function handleDailySummary(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const date = resolveDateKey(req.query.date);
    const summary = await buildDailySummary(user.sub, date);

    successResponse(res, summary);
  } catch (err) {
    if (err instanceof CaloriesValidationError) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Failed to load calorie summary', err.message);
      return;
    }

    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load calorie summary',
      (err as Error).message,
    );
  }
}

async function handleLogMeal(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const body = req.body as z.infer<typeof logMealSchema>;

    const meal = await Meal.create({
      userId: new Types.ObjectId(user.sub),
      date: resolveDateKey(body.date),
      mealType: body.mealType,
      name: body.name,
      calories: body.calories,
      protein: body.protein,
      carbs: body.carbs,
      fat: body.fat,
      fiber: body.fiber,
      sugar: body.sugar,
    });

    successResponse(res, serializeMeal(meal.toObject()), StatusCodes.CREATED);
  } catch (err) {
    if (err instanceof CaloriesValidationError) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Failed to log meal', err.message);
      return;
    }

    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to log meal',
      (err as Error).message,
    );
  }
}

async function handleLogWater(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const body = req.body as z.infer<typeof logWaterSchema>;
    const date = resolveDateKey(body.date);
    const loggedAt = body.loggedAt ? new Date(body.loggedAt) : new Date();

    const waterLog = await WaterLog.create({
      userId: new Types.ObjectId(user.sub),
      date,
      amountMl: body.amountMl,
      loggedAt,
    });

    successResponse(
      res,
      {
        _id: String(waterLog._id),
        date: waterLog.date,
        amountMl: waterLog.amountMl,
        loggedAt: waterLog.loggedAt,
        createdAt: waterLog.createdAt,
      },
      StatusCodes.CREATED,
    );
  } catch (err) {
    if (err instanceof CaloriesValidationError) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Failed to log water', err.message);
      return;
    }

    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to log water',
      (err as Error).message,
    );
  }
}

async function handleDeleteEntry(req: Request, res: Response) {
  try {
    const user = req.user as JwtPayload;
    const id = req.params.id;

    if (typeof id !== 'string') {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid calorie entry id');
      return;
    }

    if (!Types.ObjectId.isValid(id)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid calorie entry id');
      return;
    }

    const objectId = new Types.ObjectId(id);
    const userObjectId = new Types.ObjectId(user.sub);

    const deletedMeal = await Meal.findOneAndDelete({
      _id: objectId,
      userId: userObjectId,
    }).lean();

    if (deletedMeal) {
      successResponse(res, { deleted: true, entryType: 'meal', id });
      return;
    }

    const deletedWaterLog = await WaterLog.findOneAndDelete({
      _id: objectId,
      userId: userObjectId,
    }).lean();

    if (deletedWaterLog) {
      successResponse(res, { deleted: true, entryType: 'water', id });
      return;
    }

    errorResponse(res, StatusCodes.NOT_FOUND, 'Calorie entry not found');
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to delete calorie entry',
      (err as Error).message,
    );
  }
}

router.get('/', isAuthenticated, handleDailySummary);
router.get('/summary', isAuthenticated, handleDailySummary);
router.get('/daily', isAuthenticated, handleDailySummary);
router.post('/', isAuthenticated, validateBody(logMealSchema), handleLogMeal);
router.post('/meals', isAuthenticated, validateBody(logMealSchema), handleLogMeal);
router.post('/water', isAuthenticated, validateBody(logWaterSchema), handleLogWater);
router.delete('/:id', isAuthenticated, handleDeleteEntry);

export default router;
