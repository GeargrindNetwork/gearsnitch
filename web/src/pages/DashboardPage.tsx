import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router-dom';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { getMetricsTrends, type TrendBucket, type TrendRange, type TrendResponse } from '@/lib/api';
import { useAuth } from '@/lib/auth';

// ---------------------------------------------------------------------------
// Types + helpers
// ---------------------------------------------------------------------------

const SUPPORTED_RANGES: TrendRange[] = ['week', 'month', 'year'];

function isTrendRange(value: string | null): value is TrendRange {
  return value !== null && (SUPPORTED_RANGES as string[]).includes(value);
}

function formatBucketLabel(ts: string, range: TrendRange): string {
  const d = new Date(ts);
  if (range === 'year') {
    return d.toLocaleDateString('en-US', { month: 'short', timeZone: 'UTC' });
  }
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
}

// ---------------------------------------------------------------------------
// Data hooks
// ---------------------------------------------------------------------------

function useTrends(range: TrendRange, enabled: boolean) {
  return useQuery<TrendResponse>({
    queryKey: ['metrics-trends', range],
    queryFn: () => getMetricsTrends(range),
    enabled,
    retry: false,
    // 5-minute stale window — trend charts don't need second-level freshness.
    staleTime: 5 * 60_000,
  });
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function SummaryStat({
  label,
  value,
  sublabel,
}: {
  label: string;
  value: string | number;
  sublabel?: string;
}) {
  return (
    <Card className="border-zinc-800 bg-zinc-900/50">
      <CardContent className="pt-6">
        <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">{label}</p>
        <p className="mt-2 text-2xl font-semibold text-white">{value}</p>
        {sublabel ? <p className="mt-1 text-xs text-zinc-500">{sublabel}</p> : null}
      </CardContent>
    </Card>
  );
}

interface ChartCardProps {
  title: string;
  data: Array<Record<string, unknown>>;
  dataKey: string;
  range: TrendRange;
  color: string;
  valueFormatter?: (value: number) => string;
  variant?: 'area' | 'line';
}

function ChartCard({
  title,
  data,
  dataKey,
  range,
  color,
  valueFormatter,
  variant = 'area',
}: ChartCardProps) {
  const gradientId = useMemo(() => `fill-${dataKey}`, [dataKey]);

  return (
    <Card className="border-zinc-800 bg-zinc-900/50">
      <CardHeader>
        <CardTitle className="text-base font-semibold text-white">{title}</CardTitle>
      </CardHeader>
      <CardContent className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          {variant === 'area' ? (
            <AreaChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={color} stopOpacity={0.45} />
                  <stop offset="100%" stopColor={color} stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid stroke="#27272a" strokeDasharray="3 3" vertical={false} />
              <XAxis
                dataKey="label"
                stroke="#52525b"
                fontSize={11}
                tickLine={false}
                axisLine={false}
                interval="preserveStartEnd"
              />
              <YAxis
                stroke="#52525b"
                fontSize={11}
                tickLine={false}
                axisLine={false}
                width={36}
                tickFormatter={(value: number) => (valueFormatter ? valueFormatter(value) : String(value))}
              />
              <Tooltip
                contentStyle={{
                  background: '#09090b',
                  border: '1px solid #27272a',
                  borderRadius: 8,
                  color: '#fafafa',
                  fontSize: 12,
                }}
                labelStyle={{ color: '#a1a1aa' }}
                formatter={(value: unknown) => [
                  valueFormatter && typeof value === 'number' ? valueFormatter(value) : String(value),
                  title,
                ]}
              />
              <Area
                type="monotone"
                dataKey={dataKey}
                stroke={color}
                strokeWidth={2}
                fill={`url(#${gradientId})`}
                activeDot={{ r: 4 }}
              />
            </AreaChart>
          ) : (
            <LineChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
              <CartesianGrid stroke="#27272a" strokeDasharray="3 3" vertical={false} />
              <XAxis
                dataKey="label"
                stroke="#52525b"
                fontSize={11}
                tickLine={false}
                axisLine={false}
                interval="preserveStartEnd"
              />
              <YAxis
                stroke="#52525b"
                fontSize={11}
                tickLine={false}
                axisLine={false}
                width={36}
                domain={['dataMin - 1', 'dataMax + 1']}
                tickFormatter={(value: number) => (valueFormatter ? valueFormatter(value) : String(value))}
              />
              <Tooltip
                contentStyle={{
                  background: '#09090b',
                  border: '1px solid #27272a',
                  borderRadius: 8,
                  color: '#fafafa',
                  fontSize: 12,
                }}
                labelStyle={{ color: '#a1a1aa' }}
                formatter={(value: unknown) => [
                  valueFormatter && typeof value === 'number' ? valueFormatter(value) : String(value),
                  title,
                ]}
              />
              <Line
                type="monotone"
                dataKey={dataKey}
                stroke={color}
                strokeWidth={2}
                dot={false}
                connectNulls={false}
                activeDot={{ r: 4 }}
              />
            </LineChart>
          )}
        </ResponsiveContainer>
        <p className="mt-2 text-[11px] uppercase tracking-[0.14em] text-zinc-600">
          {range === 'week' ? 'Last 7 days' : range === 'month' ? 'Last 30 days' : 'Last 12 months'}
        </p>
      </CardContent>
    </Card>
  );
}

function EmptyState() {
  return (
    <Card className="border-zinc-800 bg-zinc-900/50">
      <CardContent className="flex flex-col items-center gap-4 py-16 text-center">
        <p className="text-lg font-semibold text-white">No data yet</p>
        <p className="max-w-md text-sm text-zinc-400">
          Log your first workout, run, or meal in the iPhone app and your trends
          will appear here. Calories and weight pull from HealthKit automatically.
        </p>
        <Button
          className="bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400"
          onClick={() => window.location.assign('/#download')}
        >
          Download the iPhone App
        </Button>
      </CardContent>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function DashboardPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { isAuthenticated } = useAuth();

  const rawRange = searchParams.get('range');
  const range: TrendRange = isTrendRange(rawRange) ? rawRange : 'week';

  const { data, isLoading, error } = useTrends(range, isAuthenticated);

  const chartData = useMemo(() => {
    const buckets: TrendBucket[] = data?.buckets ?? [];
    return buckets.map((bucket) => ({
      ts: bucket.ts,
      label: formatBucketLabel(bucket.ts, range),
      workouts: bucket.workouts,
      workoutMinutes: bucket.workoutMinutes,
      runs: bucket.runs,
      runKm: Math.round((bucket.runMeters / 1000) * 10) / 10,
      calories: bucket.calories,
      // Undefined for empty buckets keeps the weight line continuous (gaps)
      weightKg: bucket.weightKg ?? undefined,
    }));
  }, [data?.buckets, range]);

  const hasAnyData = useMemo(() => {
    if (!data) return false;
    const s = data.summary;
    const hasWeight = data.buckets.some((bucket) => bucket.weightKg !== null);
    return s.totalWorkouts > 0 || s.totalRuns > 0 || s.totalCalories > 0 || hasWeight;
  }, [data]);

  const handleRangeChange = (next: unknown) => {
    const value = typeof next === 'string' ? next : null;
    if (!isTrendRange(value)) return;
    const copy = new URLSearchParams(searchParams);
    copy.set('range', value);
    setSearchParams(copy, { replace: true });
  };

  return (
    <div className="dark min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <section className="px-6 py-16 pt-24 lg:px-8">
        <div className="mx-auto max-w-6xl">
          <div className="mb-8 flex flex-wrap items-end justify-between gap-4">
            <div>
              <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
              <p className="mt-2 text-sm text-zinc-400">
                Trend view across workouts, runs, calories, and weight. Log activity
                in the iPhone app — the charts update the next time you load this
                page.
              </p>
            </div>
            <Tabs value={range} onValueChange={handleRangeChange}>
              <TabsList className="border border-zinc-800 bg-zinc-900">
                <TabsTrigger value="week">Week</TabsTrigger>
                <TabsTrigger value="month">Month</TabsTrigger>
                <TabsTrigger value="year">Year</TabsTrigger>
              </TabsList>
            </Tabs>
          </div>

          {isLoading ? (
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardContent className="py-12 text-center text-zinc-500">
                Loading your trends...
              </CardContent>
            </Card>
          ) : error ? (
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardHeader>
                <CardTitle>Dashboard unavailable</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3 text-zinc-400">
                <p>{error instanceof Error ? error.message : 'Failed to load trends.'}</p>
                <p className="text-sm text-zinc-500">
                  Try refreshing the page. If the problem persists, sign out and sign
                  back in.
                </p>
              </CardContent>
            </Card>
          ) : data && hasAnyData ? (
            <>
              <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <SummaryStat
                  label="Workouts"
                  value={data.summary.totalWorkouts}
                  sublabel={range !== 'week' ? `${data.summary.avgWorkoutsPerWeek.toFixed(1)} / week avg` : undefined}
                />
                <SummaryStat label="Runs" value={data.summary.totalRuns} />
                <SummaryStat
                  label="Calories"
                  value={data.summary.totalCalories.toLocaleString()}
                  sublabel="kcal total"
                />
                <SummaryStat
                  label="Range"
                  value={range === 'week' ? '7d' : range === 'month' ? '30d' : '12m'}
                  sublabel={data.timezone}
                />
              </div>

              <div className="grid gap-6 lg:grid-cols-2">
                <ChartCard
                  title="Workouts"
                  data={chartData}
                  dataKey="workouts"
                  range={range}
                  color="#22d3ee"
                />
                <ChartCard
                  title="Runs (km)"
                  data={chartData}
                  dataKey="runKm"
                  range={range}
                  color="#34d399"
                  valueFormatter={(value) => `${value.toFixed(1)} km`}
                />
                <ChartCard
                  title="Calories"
                  data={chartData}
                  dataKey="calories"
                  range={range}
                  color="#f97316"
                  valueFormatter={(value) => `${Math.round(value).toLocaleString()}`}
                />
                <ChartCard
                  title="Weight (kg)"
                  data={chartData}
                  dataKey="weightKg"
                  range={range}
                  color="#a855f7"
                  variant="line"
                  valueFormatter={(value) => `${value.toFixed(1)} kg`}
                />
              </div>

              <p className="mt-8 text-xs text-zinc-600">
                Not seeing your latest data?{' '}
                <Link to="/account" className="underline hover:text-zinc-400">
                  Check your iPhone sync status
                </Link>{' '}
                or give HealthKit a minute to catch up.
              </p>
            </>
          ) : (
            <EmptyState />
          )}
        </div>
      </section>

      <Footer />
    </div>
  );
}
