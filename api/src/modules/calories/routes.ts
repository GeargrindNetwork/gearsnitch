import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { Meal } from '../../models/Meal.js';
import { NutritionGoal } from '../../models/NutritionGoal.js';
import { WaterLog } from '../../models/WaterLog.js';
import { errorResponse, successResponse } from '../../utils/response.js';

const router = Router();

const isoDatePattern = /^\d{4}-\d{2}-\d{2}$/;
const mealTypeSchema = z.enum(['breakfast', 'lunch', 'dinner', 'snack']);

const logMealSchema = z.object({
  name: z.string().trim().min(1).max(160),
  calories: z.coerce.number().finite().min(0).max(10000),
  protein: z.coerce.number().finite().min(0).max(1000).optional().nullable(),
  carbs: z.coerce.number().finite().min(0).max(1000).optional().nullable(),
  fat: z.coerce.number().finite().min(0).max(1000).optional().nullable(),
  mealType: mealTypeSchema,
});

const logWaterSchema = z.object({
  amountMl: z.coerce.number().finite().positive().max(10000),
});

type LogMealBody = z.infer<typeof logMealSchema>;
type LogWaterBody = z.infer<typeof logWaterSchema>;

function getUserId(req: Request): Types.ObjectId {
  return new Types.ObjectId((req.user as JwtPayload).sub);
}

function getRouteParam(req: Request, key: string): string {
  const value = req.params[key];
  return Array.isArray(value) ? value[0] : value;
}

function resolveDateKey(rawValue: unknown): string {
  if (typeof rawValue === 'string' && isoDatePattern.test(rawValue)) {
    return rawValue;
  }

  return new Date().toISOString().slice(0, 10);
}

function serializeMeal(meal: Record<string, any>) {
  return {
    _id: String(meal._id),
    name: meal.name,
    calories: meal.calories ?? 0,
    protein: meal.protein ?? null,
    carbs: meal.carbs ?? null,
    fat: meal.fat ?? null,
    mealType: meal.mealType,
    createdAt: meal.createdAt,
  };
}

async function buildDailySummary(userId: Types.ObjectId, date: string) {
  const [goal, meals, waterLogs] = await Promise.all([
    NutritionGoal.findOne({ userId }).lean(),
    Meal.find({ userId, date }).sort({ createdAt: -1 }).lean(),
    WaterLog.find({ userId, date }).sort({ loggedAt: -1 }).lean(),
  ]);

  const totalCalories = meals.reduce((sum, meal) => sum + (meal.calories ?? 0), 0);
  const protein = meals.reduce((sum, meal) => sum + (meal.protein ?? 0), 0);
  const carbs = meals.reduce((sum, meal) => sum + (meal.carbs ?? 0), 0);
  const fat = meals.reduce((sum, meal) => sum + (meal.fat ?? 0), 0);
  const fiber = meals.reduce((sum, meal) => sum + (meal.fiber ?? 0), 0);
  const sugar = meals.reduce((sum, meal) => sum + (meal.sugar ?? 0), 0);
  const waterMl = waterLogs.reduce((sum, entry) => sum + (entry.amountMl ?? 0), 0);

  return {
    date,
    totalCalories,
    targetCalories: goal?.dailyCalorieTarget ?? 2000,
    protein,
    carbs,
    fat,
    fiber,
    sugar,
    waterMl,
    waterTargetMl: goal?.waterTargetMl ?? 2500,
    meals: meals.map((meal) => serializeMeal(meal)),
  };
}

async function handleDailySummary(req: Request, res: Response) {
  try {
    const summary = await buildDailySummary(getUserId(req), resolveDateKey(req.query.date));
    successResponse(res, summary);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load calorie summary',
      err instanceof Error ? err.message : String(err),
    );
  }
}

// GET /calories and /calories/daily
router.get('/', isAuthenticated, handleDailySummary);
router.get('/daily', isAuthenticated, handleDailySummary);
router.get('/summary', isAuthenticated, handleDailySummary);

// POST /calories and /calories/meals
router.post('/', isAuthenticated, validateBody(logMealSchema), async (req, res) => {
  try {
    const body = req.body as LogMealBody;
    const meal = await Meal.create({
      userId: getUserId(req),
      date: resolveDateKey(req.query.date),
      mealType: body.mealType,
      name: body.name,
      calories: body.calories,
      protein: body.protein ?? undefined,
      carbs: body.carbs ?? undefined,
      fat: body.fat ?? undefined,
    });

    successResponse(res, serializeMeal(meal.toObject()), StatusCodes.CREATED);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to log meal',
      err instanceof Error ? err.message : String(err),
    );
  }
});

router.post('/meals', isAuthenticated, validateBody(logMealSchema), async (req, res) => {
  try {
    const body = req.body as LogMealBody;
    const meal = await Meal.create({
      userId: getUserId(req),
      date: resolveDateKey(req.query.date),
      mealType: body.mealType,
      name: body.name,
      calories: body.calories,
      protein: body.protein ?? undefined,
      carbs: body.carbs ?? undefined,
      fat: body.fat ?? undefined,
    });

    successResponse(res, serializeMeal(meal.toObject()), StatusCodes.CREATED);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to log meal',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /calories/water
router.post('/water', isAuthenticated, validateBody(logWaterSchema), async (req, res) => {
  try {
    const body = req.body as LogWaterBody;
    const loggedAt = new Date();

    await WaterLog.create({
      userId: getUserId(req),
      date: resolveDateKey(req.query.date),
      amountMl: body.amountMl,
      loggedAt,
    });

    successResponse(res, {}, StatusCodes.CREATED);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to log water intake',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// DELETE /calories/:id
router.delete('/:id', isAuthenticated, async (req, res) => {
  try {
    const mealId = getRouteParam(req, 'id');
    if (!Types.ObjectId.isValid(mealId)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid calorie entry id');
      return;
    }

    const deletedMeal = await Meal.findOneAndDelete({
      _id: new Types.ObjectId(mealId),
      userId: getUserId(req),
    });

    if (!deletedMeal) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Calorie entry not found');
      return;
    }

    successResponse(res, {});
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to delete calorie entry',
      err instanceof Error ? err.message : String(err),
    );
  }
});

export default router;
