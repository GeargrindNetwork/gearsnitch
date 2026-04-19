import { useQuery } from '@tanstack/react-query';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';

// ---------------------------------------------------------------------------
// Types (mirror the /calories response shape in api/src/modules/calories/routes.ts)
// ---------------------------------------------------------------------------

type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack';

interface CalorieMealEntry {
  _id: string;
  name: string;
  calories: number;
  protein: number | null;
  carbs: number | null;
  fat: number | null;
  fiber: number | null;
  sugar: number | null;
  mealType: MealType;
  createdAt: string;
}

interface CalorieDailySummary {
  date: string;
  totalCalories: number;
  targetCalories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  sugar: number;
  waterMl: number;
  waterTargetMl: number;
  meals: CalorieMealEntry[];
}

// ---------------------------------------------------------------------------
// Data fetcher
// ---------------------------------------------------------------------------

async function fetchDailySummary(): Promise<CalorieDailySummary> {
  const res = await api.get<CalorieDailySummary>('/calories/daily');
  if (!res.success || !res.data) {
    throw new Error(res.error?.message ?? 'Failed to load daily calorie summary');
  }
  return res.data;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const ML_PER_GLASS = 240; // standard 8 oz glass
const ML_PER_OZ = 29.5735;

function formatDateLabel(iso: string): string {
  // Treat YYYY-MM-DD as a local date, not UTC, to avoid off-by-one on the client.
  const parsed = new Date(`${iso}T12:00:00`);
  return parsed.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  });
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  });
}

function clampPercent(value: number): number {
  if (!Number.isFinite(value)) return 0;
  if (value < 0) return 0;
  if (value > 100) return 100;
  return value;
}

function percentOf(part: number, whole: number): number {
  if (whole <= 0) return 0;
  return clampPercent((part / whole) * 100);
}

function roundTo(value: number, places: number): number {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
}

function mealTypeLabel(mealType: MealType): string {
  return mealType.charAt(0).toUpperCase() + mealType.slice(1);
}

function mealTypeBadgeClass(mealType: MealType): string {
  switch (mealType) {
    case 'breakfast':
      return 'border-amber-700 text-amber-300';
    case 'lunch':
      return 'border-emerald-700 text-emerald-400';
    case 'dinner':
      return 'border-cyan-700 text-cyan-300';
    default:
      return 'border-zinc-700 text-zinc-300';
  }
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function ProgressBar({
  value,
  colorClass,
  'aria-label': ariaLabel,
}: {
  value: number;
  colorClass: string;
  'aria-label'?: string;
}) {
  const clamped = clampPercent(value);
  return (
    <div
      role="progressbar"
      aria-label={ariaLabel}
      aria-valuenow={Math.round(clamped)}
      aria-valuemin={0}
      aria-valuemax={100}
      className="h-2 w-full overflow-hidden rounded-full bg-zinc-800"
    >
      <div
        className={`h-full rounded-full ${colorClass} transition-[width] duration-300`}
        style={{ width: `${clamped}%` }}
      />
    </div>
  );
}

function MacroRow({
  label,
  grams,
  percent,
  colorClass,
}: {
  label: string;
  grams: number;
  percent: number;
  colorClass: string;
}) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-sm font-medium text-zinc-200">{label}</span>
        <span className="text-sm text-zinc-400">
          <span className="font-semibold text-white">{roundTo(grams, 1)}g</span>
          <span className="ml-2 text-xs text-zinc-500">{Math.round(percent)}%</span>
        </span>
      </div>
      <ProgressBar value={percent} colorClass={colorClass} aria-label={`${label} share of macros`} />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function CaloriesPage() {
  const { isAuthenticated } = useAuth();

  const summaryQuery = useQuery<CalorieDailySummary>({
    queryKey: ['calories', 'daily'],
    queryFn: fetchDailySummary,
    enabled: isAuthenticated,
    retry: false,
  });

  const summary = summaryQuery.data;
  const isLoading = summaryQuery.isLoading;
  const error = summaryQuery.error;

  // Derived values (guarded against undefined summary)
  const totalCalories = summary?.totalCalories ?? 0;
  const targetCalories = summary?.targetCalories ?? 0;
  const caloriesRemaining = Math.max(0, targetCalories - totalCalories);
  const caloriesOver = Math.max(0, totalCalories - targetCalories);
  const caloriesPercent = percentOf(totalCalories, targetCalories);

  // Macro calories: 4 cal/g protein, 4 cal/g carbs, 9 cal/g fat.
  const proteinG = summary?.protein ?? 0;
  const carbsG = summary?.carbs ?? 0;
  const fatG = summary?.fat ?? 0;
  const proteinCals = proteinG * 4;
  const carbsCals = carbsG * 4;
  const fatCals = fatG * 9;
  const macroCalTotal = proteinCals + carbsCals + fatCals;
  const proteinPercent = percentOf(proteinCals, macroCalTotal);
  const carbsPercent = percentOf(carbsCals, macroCalTotal);
  const fatPercent = percentOf(fatCals, macroCalTotal);

  const waterMl = summary?.waterMl ?? 0;
  const waterTargetMl = summary?.waterTargetMl ?? 0;
  const waterPercent = percentOf(waterMl, waterTargetMl);
  const waterGlasses = waterMl / ML_PER_GLASS;
  const waterOunces = waterMl / ML_PER_OZ;
  const waterTargetGlasses = waterTargetMl / ML_PER_GLASS;

  const recentMeals = (summary?.meals ?? []).slice(0, 8);

  return (
    <div className="dark min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <main className="mx-auto max-w-4xl space-y-6 px-6 pb-16 pt-28 lg:px-8">
        <section className="space-y-2">
          <Badge
            variant="secondary"
            className="border border-emerald-500/20 bg-emerald-500/10 text-emerald-400"
          >
            Nutrition
          </Badge>
          <h1 className="text-3xl font-bold tracking-tight">Calories & Nutrition</h1>
          <p className="max-w-2xl text-sm text-zinc-400">
            Today&apos;s calorie total, macro breakdown, water intake, and the most recent meals
            you logged from the GearSnitch iOS app.
          </p>
          {summary?.date ? (
            <p className="text-xs uppercase tracking-[0.16em] text-zinc-500">
              {formatDateLabel(summary.date)}
            </p>
          ) : null}
        </section>

        {isLoading && (
          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardContent className="py-12 text-center text-zinc-500">
              Loading your nutrition dashboard...
            </CardContent>
          </Card>
        )}

        {!isLoading && error && (
          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardHeader>
              <CardTitle>Nutrition Unavailable</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-zinc-400">
              <p>{error instanceof Error ? error.message : 'Failed to load your nutrition data.'}</p>
              <p className="text-sm text-zinc-500">
                Try refreshing the page. If the problem persists, sign out and sign back in.
              </p>
            </CardContent>
          </Card>
        )}

        {!isLoading && !error && summary && (
          <>
            {/* Daily calorie summary */}
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardHeader>
                <CardTitle>Today&apos;s Calories</CardTitle>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="grid gap-4 sm:grid-cols-3">
                  <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4">
                    <p className="text-xs uppercase tracking-[0.16em] text-zinc-500">Consumed</p>
                    <p className="mt-2 text-3xl font-bold text-white">
                      {Math.round(totalCalories).toLocaleString()}
                    </p>
                    <p className="text-xs text-zinc-500">calories logged</p>
                  </div>
                  <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4">
                    <p className="text-xs uppercase tracking-[0.16em] text-zinc-500">Goal</p>
                    <p className="mt-2 text-3xl font-bold text-white">
                      {Math.round(targetCalories).toLocaleString()}
                    </p>
                    <p className="text-xs text-zinc-500">daily target</p>
                  </div>
                  <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4">
                    <p className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                      {caloriesOver > 0 ? 'Over' : 'Remaining'}
                    </p>
                    <p
                      className={`mt-2 text-3xl font-bold ${
                        caloriesOver > 0 ? 'text-rose-400' : 'text-emerald-400'
                      }`}
                    >
                      {Math.round(caloriesOver > 0 ? caloriesOver : caloriesRemaining).toLocaleString()}
                    </p>
                    <p className="text-xs text-zinc-500">
                      {caloriesOver > 0 ? 'above goal' : 'under goal'}
                    </p>
                  </div>
                </div>

                <div className="space-y-2">
                  <div className="flex items-baseline justify-between">
                    <span className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                      Progress
                    </span>
                    <span className="text-xs text-zinc-400">
                      {Math.round(caloriesPercent)}% of goal
                    </span>
                  </div>
                  <ProgressBar
                    value={caloriesPercent}
                    colorClass={
                      caloriesOver > 0
                        ? 'bg-rose-500'
                        : 'bg-gradient-to-r from-cyan-500 to-emerald-500'
                    }
                    aria-label="Calories consumed vs goal"
                  />
                </div>
              </CardContent>
            </Card>

            {/* Macro breakdown + Water */}
            <section className="grid gap-4 md:grid-cols-2">
              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader>
                  <CardTitle>Macro Breakdown</CardTitle>
                </CardHeader>
                <CardContent className="space-y-5">
                  {macroCalTotal <= 0 ? (
                    <p className="text-sm text-zinc-400">
                      No macros logged yet today. Log a meal in the iOS app to see your protein,
                      carbs, and fat split.
                    </p>
                  ) : (
                    <>
                      <MacroRow
                        label="Protein"
                        grams={proteinG}
                        percent={proteinPercent}
                        colorClass="bg-emerald-500"
                      />
                      <MacroRow
                        label="Carbs"
                        grams={carbsG}
                        percent={carbsPercent}
                        colorClass="bg-cyan-500"
                      />
                      <MacroRow
                        label="Fat"
                        grams={fatG}
                        percent={fatPercent}
                        colorClass="bg-amber-500"
                      />
                    </>
                  )}
                </CardContent>
              </Card>

              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader>
                  <CardTitle>Water Intake</CardTitle>
                </CardHeader>
                <CardContent className="space-y-5">
                  <div className="flex items-baseline justify-between">
                    <div>
                      <p className="text-3xl font-bold text-white">
                        {roundTo(waterGlasses, 1)}
                        <span className="ml-1 text-base font-normal text-zinc-400">glasses</span>
                      </p>
                      <p className="text-xs text-zinc-500">
                        {Math.round(waterOunces)} oz • {Math.round(waterMl)} ml
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-xs uppercase tracking-[0.16em] text-zinc-500">Goal</p>
                      <p className="text-sm font-semibold text-zinc-300">
                        {roundTo(waterTargetGlasses, 1)} glasses
                      </p>
                      <p className="text-xs text-zinc-500">{Math.round(waterTargetMl)} ml</p>
                    </div>
                  </div>

                  <div className="space-y-2">
                    <div className="flex items-baseline justify-between">
                      <span className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                        Progress
                      </span>
                      <span className="text-xs text-zinc-400">
                        {Math.round(waterPercent)}% of goal
                      </span>
                    </div>
                    <ProgressBar
                      value={waterPercent}
                      colorClass="bg-sky-500"
                      aria-label="Water intake vs goal"
                    />
                  </div>

                  {waterMl <= 0 ? (
                    <p className="text-sm text-zinc-400">
                      No water logged today. Track glasses in the GearSnitch iOS app to see your
                      hydration progress here.
                    </p>
                  ) : null}
                </CardContent>
              </Card>
            </section>

            {/* Recent meals */}
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardHeader>
                <CardTitle>Recent Meals</CardTitle>
              </CardHeader>
              <CardContent>
                {recentMeals.length === 0 ? (
                  <p className="text-sm text-zinc-400">
                    No meals logged yet today. Open the iOS app to log breakfast, lunch, dinner,
                    or a snack and it will show up here.
                  </p>
                ) : (
                  <ul className="space-y-2">
                    {recentMeals.map((meal, index) => (
                      <li key={meal._id}>
                        {index > 0 && <Separator className="my-2 bg-zinc-800" />}
                        <div className="flex items-start justify-between gap-3 rounded-lg px-1 py-2">
                          <div className="min-w-0 flex-1">
                            <div className="flex flex-wrap items-center gap-2">
                              <p className="truncate text-sm font-medium text-zinc-100">
                                {meal.name}
                              </p>
                              <Badge
                                variant="outline"
                                className={mealTypeBadgeClass(meal.mealType)}
                              >
                                {mealTypeLabel(meal.mealType)}
                              </Badge>
                            </div>
                            <p className="mt-1 text-xs text-zinc-500">
                              Logged {formatTime(meal.createdAt)}
                              {typeof meal.protein === 'number' && meal.protein > 0
                                ? ` • ${roundTo(meal.protein, 1)}g protein`
                                : ''}
                              {typeof meal.carbs === 'number' && meal.carbs > 0
                                ? ` • ${roundTo(meal.carbs, 1)}g carbs`
                                : ''}
                              {typeof meal.fat === 'number' && meal.fat > 0
                                ? ` • ${roundTo(meal.fat, 1)}g fat`
                                : ''}
                            </p>
                          </div>
                          <p className="shrink-0 text-sm font-semibold text-white">
                            {Math.round(meal.calories).toLocaleString()} cal
                          </p>
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>

            <p className="text-xs text-zinc-600">
              Multi-day trends are coming soon. Meals and water are logged from the GearSnitch iOS
              app.
            </p>
          </>
        )}
      </main>

      <Footer />
    </div>
  );
}
