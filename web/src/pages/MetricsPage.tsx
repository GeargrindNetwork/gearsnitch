import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import MedicationDoseDialog from '@/components/account/MedicationDoseDialog';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import MedicationYearGraphCard from '@/components/metrics/MedicationYearGraphCard';
import CycleSummaryCard from '@/components/metrics/CycleSummaryCard';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { api, getMedicationYearGraph } from '@/lib/api';

interface DistributionPoint {
  label: string;
  count: number;
}

interface HourDistributionPoint extends DistributionPoint {
  hour: number;
}

interface RunTrend {
  direction: 'up' | 'down' | 'flat';
  deltaMeters: number;
  deltaPercent: number | null;
  thisWeekDistanceMeters: number;
  lastWeekDistanceMeters: number;
}

interface WorkoutMetricsOverview {
  summary: {
    averageSessionDurationMinutes30d: number;
    sessionsThisWeek: number;
    sessionsThisMonth: number;
    completedWorkouts: number;
    workoutsThisMonth: number;
    totalWorkoutMinutesThisMonth: number;
  };
  streaks: {
    currentDays: number;
    longestDays: number;
  };
  distributions: {
    byWeekday: DistributionPoint[];
    byHour: HourDistributionPoint[];
  };
  runSummary: {
    completedRuns: number;
    activeRuns: number;
    totalDistanceMeters: number;
    totalDistanceMeters30d: number;
    averageRunDistanceMeters30d: number;
  };
  runTrend: RunTrend;
  deviceSummary: {
    totalDevices: number;
    favorites: number;
    monitoring: number;
    lost: number;
  };
  devices: Array<{
    _id: string;
    name: string;
    nickname: string | null;
    type: string;
    status: string;
    isFavorite: boolean;
    isMonitoring: boolean;
    signalStrength: number | null;
    lastSeenAt: string | null;
  }>;
  recentRuns: Array<{
    _id: string;
    startedAt: string;
    endedAt: string | null;
    status: 'active' | 'completed';
    durationSeconds: number;
    durationMinutes: number;
    distanceMeters: number;
    averagePaceSecondsPerKm: number | null;
    source: string;
    routePointCount: number;
  }>;
  recentWorkouts: Array<{
    _id: string;
    name: string;
    gymName: string | null;
    startedAt: string;
    endedAt: string | null;
    durationMinutes: number;
    exerciseCount: number;
    source: string;
  }>;
}

async function fetchMetrics(): Promise<WorkoutMetricsOverview> {
  const response = await api.get<WorkoutMetricsOverview>('/workouts/metrics/overview');
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load metrics');
  }
  return response.data;
}

function formatMinutes(minutes: number) {
  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    return remainder > 0 ? `${hours}h ${remainder}m` : `${hours}h`;
  }
  return `${minutes}m`;
}

function formatDuration(durationSeconds: number) {
  const hours = Math.floor(durationSeconds / 3600);
  const minutes = Math.floor((durationSeconds % 3600) / 60);
  const seconds = durationSeconds % 60;

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }

  if (minutes > 0) {
    return `${minutes}m ${seconds}s`;
  }

  return `${seconds}s`;
}

function formatDistance(distanceMeters: number) {
  const distanceKm = distanceMeters / 1000;
  return distanceKm >= 10 ? `${distanceKm.toFixed(1)} km` : `${distanceKm.toFixed(2)} km`;
}

function formatPace(secondsPerKm: number | null) {
  if (!secondsPerKm) {
    return '--:-- /km';
  }

  const minutes = Math.floor(secondsPerKm / 60);
  const seconds = secondsPerKm % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')} /km`;
}

function formatShortDate(value: string) {
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
  }).format(new Date(value));
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(value));
}

function formatSignal(signalStrength: number | null) {
  if (signalStrength === null) {
    return 'No signal telemetry';
  }

  return `${signalStrength} dBm`;
}

function trendTone(direction: RunTrend['direction']) {
  switch (direction) {
    case 'up':
      return 'text-emerald-300';
    case 'down':
      return 'text-amber-300';
    default:
      return 'text-zinc-200';
  }
}

function trendCopy(trend: RunTrend) {
  if (trend.deltaPercent === null && trend.thisWeekDistanceMeters > 0) {
    return 'New run distance this week.';
  }

  if (trend.direction === 'flat') {
    return 'Distance is effectively flat versus last week.';
  }

  const sign = trend.deltaPercent && trend.deltaPercent > 0 ? '+' : '';
  return `${sign}${trend.deltaPercent ?? 0}% versus last week.`;
}

function deviceTone(status: string) {
  switch (status) {
    case 'monitoring':
    case 'connected':
    case 'reconnected':
      return 'border-emerald-400/20 bg-emerald-400/10 text-emerald-300';
    case 'lost':
      return 'border-red-400/20 bg-red-400/10 text-red-300';
    case 'disconnected':
    case 'inactive':
      return 'border-amber-400/20 bg-amber-400/10 text-amber-300';
    default:
      return 'border-white/10 bg-white/5 text-zinc-300';
  }
}

function SummaryCard({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent: string;
}) {
  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardContent className="flex flex-col gap-2 p-5">
        <span className="text-xs font-medium uppercase tracking-[0.18em] text-zinc-500">{label}</span>
        <span className={`text-3xl font-semibold ${accent}`}>{value}</span>
      </CardContent>
    </Card>
  );
}

function DistributionChart({
  title,
  data,
  accentClass,
}: {
  title: string;
  data: DistributionPoint[];
  accentClass: string;
}) {
  const maxCount = Math.max(1, ...data.map((point) => point.count));

  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardHeader>
        <CardTitle className="text-base font-semibold text-white">{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {data.map((point) => (
          <div key={point.label} className="space-y-1">
            <div className="flex items-center justify-between text-xs text-zinc-400">
              <span>{point.label}</span>
              <span>{point.count}</span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-zinc-800">
              <div
                className={`h-full rounded-full ${accentClass}`}
                style={{ width: `${(point.count / maxCount) * 100}%` }}
              />
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

function DeviceStatusCard({
  device,
}: {
  device: WorkoutMetricsOverview['devices'][number];
}) {
  const displayName = device.nickname?.trim() ? device.nickname : device.name;

  return (
    <div className="rounded-3xl border border-white/8 bg-black/30 p-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-white">{displayName}</p>
          <p className="mt-1 text-xs uppercase tracking-[0.18em] text-zinc-500">
            {device.type}
            {device.nickname?.trim() ? ` • ${device.name}` : ''}
          </p>
        </div>
        <div className="flex flex-col items-end gap-2">
          {device.isFavorite ? (
            <Badge className="border border-amber-400/20 bg-amber-400/10 text-amber-300">Favorite</Badge>
          ) : null}
          <Badge className={deviceTone(device.status)}>{device.status.replaceAll('_', ' ')}</Badge>
        </div>
      </div>

      <div className="mt-5 grid gap-3 text-sm text-zinc-300 sm:grid-cols-2">
        <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-3">
          <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Monitoring</p>
          <p className="mt-2 font-medium text-white">{device.isMonitoring ? 'Enabled' : 'Idle'}</p>
        </div>
        <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-3">
          <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Signal</p>
          <p className="mt-2 font-medium text-white">{formatSignal(device.signalStrength)}</p>
        </div>
      </div>

      <p className="mt-4 text-sm text-zinc-400">
        {device.lastSeenAt ? `Last seen ${formatDateTime(device.lastSeenAt)}` : 'No live telemetry has synced for this device yet.'}
      </p>
    </div>
  );
}

function RunGalleryCard({
  run,
}: {
  run: WorkoutMetricsOverview['recentRuns'][number];
}) {
  const isActive = run.status === 'active';

  return (
    <div className="rounded-3xl border border-white/8 bg-black/30 p-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-semibold text-white">{formatDateTime(run.startedAt)}</p>
          <p className="mt-1 text-xs uppercase tracking-[0.18em] text-zinc-500">{run.source ?? 'ios'}</p>
        </div>
        <Badge
          className={
            isActive
              ? 'border border-amber-400/20 bg-amber-400/10 text-amber-300'
              : 'border border-emerald-400/20 bg-emerald-400/10 text-emerald-300'
          }
        >
          {isActive ? 'Live' : 'Completed'}
        </Badge>
      </div>

      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-3">
          <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Distance</p>
          <p className="mt-2 text-lg font-semibold text-white">{formatDistance(run.distanceMeters)}</p>
        </div>
        <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-3">
          <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Duration</p>
          <p className="mt-2 text-lg font-semibold text-white">{formatDuration(run.durationSeconds)}</p>
        </div>
        <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-3">
          <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Average Pace</p>
          <p className="mt-2 text-lg font-semibold text-white">{formatPace(run.averagePaceSecondsPerKm)}</p>
        </div>
        <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-3">
          <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Route Points</p>
          <p className="mt-2 text-lg font-semibold text-white">{run.routePointCount}</p>
        </div>
      </div>

      <div className="mt-5">
        <Link to="/runs">
          <Button variant="outline" className="w-full border-white/10 bg-zinc-950/70 text-zinc-100 hover:bg-zinc-900">
            {isActive ? 'Open live run board' : 'Open route replay'}
          </Button>
        </Link>
      </div>
    </div>
  );
}

export default function MetricsPage() {
  const currentYear = new Date().getFullYear();
  const [isMedicationDialogOpen, setMedicationDialogOpen] = useState(false);
  const { data, isLoading, error, refetch, isFetching } = useQuery({
    queryKey: ['workout-metrics-overview'],
    queryFn: fetchMetrics,
    staleTime: 60_000,
  });
  const medicationGraphQuery = useQuery({
    queryKey: ['medication-year-graph', currentYear],
    queryFn: () => getMedicationYearGraph(currentYear),
    staleTime: 60_000,
  });

  return (
    <div className="min-h-screen bg-black text-white">
      <Header />
      <main className="mx-auto flex min-h-screen max-w-7xl flex-col px-4 pb-16 pt-28 sm:px-6 lg:px-8">
        <section className="relative overflow-hidden rounded-[2rem] border border-white/5 bg-zinc-900/70 px-6 py-8 sm:px-8 lg:px-10">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,_rgba(34,211,238,0.16),_transparent_32%),radial-gradient(circle_at_bottom_right,_rgba(16,185,129,0.14),_transparent_35%)]" />
          <div className="relative max-w-3xl">
            <Badge variant="secondary" className="border border-cyan-500/20 bg-cyan-500/10 text-cyan-400">
              Metrics
            </Badge>
            <h1 className="mt-4 text-4xl font-bold tracking-tight text-white sm:text-5xl">
              Workouts, runs, and device state in one browser dashboard.
            </h1>
            <p className="mt-4 max-w-2xl text-base leading-7 text-zinc-400 sm:text-lg">
              The browser now tracks more than gym-session summaries. You can inspect run distance
              trends, recent route captures, and the latest known state of monitored gear without
              dropping into the API or the iOS simulator.
            </p>
          </div>
        </section>

        {isLoading ? (
          <Card className="mt-10 border-white/5 bg-zinc-900/70">
            <CardContent className="p-8 text-sm text-zinc-400">
              Loading your dashboard analytics...
            </CardContent>
          </Card>
        ) : null}

        {error ? (
          <Card className="mt-10 border-red-500/20 bg-red-500/5">
            <CardContent className="flex flex-col gap-4 p-8">
              <div>
                <h2 className="text-lg font-semibold text-white">Metrics unavailable</h2>
                <p className="mt-2 text-sm text-zinc-300">
                  {(error as Error).message || 'Try refreshing. If this keeps happening, sign out and start a new browser session.'}
                </p>
              </div>
              <div>
                <Button
                  onClick={() => {
                    void refetch();
                  }}
                  disabled={isFetching}
                  className="bg-white text-black hover:bg-zinc-200"
                >
                  {isFetching ? 'Retrying...' : 'Retry'}
                </Button>
              </div>
            </CardContent>
          </Card>
        ) : null}

        {data ? (
          <>
            <section className="mt-10 grid gap-4 md:grid-cols-2 xl:grid-cols-6">
              <SummaryCard
                label="30d Avg Session"
                value={formatMinutes(Math.round(data.summary.averageSessionDurationMinutes30d))}
                accent="text-cyan-400"
              />
              <SummaryCard
                label="Sessions This Week"
                value={String(data.summary.sessionsThisWeek)}
                accent="text-emerald-400"
              />
              <SummaryCard
                label="Workout Minutes"
                value={formatMinutes(data.summary.totalWorkoutMinutesThisMonth)}
                accent="text-lime-300"
              />
              <SummaryCard
                label="Run Distance This Week"
                value={formatDistance(data.runTrend.thisWeekDistanceMeters)}
                accent="text-amber-300"
              />
              <SummaryCard
                label="Completed Runs"
                value={String(data.runSummary.completedRuns)}
                accent="text-fuchsia-300"
              />
              <SummaryCard
                label="Monitoring Devices"
                value={`${data.deviceSummary.monitoring}/${data.deviceSummary.totalDevices}`}
                accent="text-sky-300"
              />
            </section>

            <section className="mt-4">
              <CycleSummaryCard />
            </section>

            <section className="mt-4 space-y-3">
              <div className="flex justify-end">
                <Button
                  variant="outline"
                  className="border-white/10 bg-zinc-950/70 text-zinc-100 hover:bg-zinc-900"
                  onClick={() => setMedicationDialogOpen(true)}
                >
                  Log medication
                </Button>
              </div>

              {medicationGraphQuery.isLoading ? (
                <Card className="border-white/5 bg-zinc-900/70">
                  <CardContent className="p-8 text-sm text-zinc-400">
                    Loading medication dose graph...
                  </CardContent>
                </Card>
              ) : medicationGraphQuery.isError ? (
                <Card className="border-amber-500/20 bg-amber-500/5">
                  <CardContent className="p-8 text-sm text-zinc-300">
                    Medication graph data is not available yet. The backend contract is in place, but
                    there is no readable year graph payload for this account.
                  </CardContent>
                </Card>
              ) : medicationGraphQuery.data ? (
                <MedicationYearGraphCard graph={medicationGraphQuery.data} />
              ) : null}
            </section>

            <section className="mt-4 grid gap-4 lg:grid-cols-3">
              <Card className="border-white/5 bg-zinc-900/70 lg:col-span-1">
                <CardHeader>
                  <CardTitle className="text-base font-semibold text-white">Streaks</CardTitle>
                </CardHeader>
                <CardContent className="grid gap-4 sm:grid-cols-2">
                  <div className="rounded-2xl border border-cyan-500/10 bg-cyan-500/5 p-5">
                    <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">Current</p>
                    <p className="mt-3 text-4xl font-semibold text-cyan-400">{data.streaks.currentDays}</p>
                    <p className="mt-2 text-sm text-zinc-400">Consecutive active days ending today or yesterday.</p>
                  </div>
                  <div className="rounded-2xl border border-emerald-500/10 bg-emerald-500/5 p-5">
                    <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">Longest</p>
                    <p className="mt-3 text-4xl font-semibold text-emerald-400">{data.streaks.longestDays}</p>
                    <p className="mt-2 text-sm text-zinc-400">Best sustained streak across all recorded activity.</p>
                  </div>
                </CardContent>
              </Card>

              <Card className="border-white/5 bg-zinc-900/70">
                <CardHeader>
                  <CardTitle className="text-base font-semibold text-white">Run Distance Trend</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-5">
                    <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">Week Over Week</p>
                    <p className={`mt-3 text-3xl font-semibold ${trendTone(data.runTrend.direction)}`}>
                      {data.runTrend.direction === 'up' && data.runTrend.deltaMeters > 0 ? '+' : ''}
                      {formatDistance(Math.abs(data.runTrend.deltaMeters))}
                    </p>
                    <p className="mt-2 text-sm text-zinc-400">{trendCopy(data.runTrend)}</p>
                  </div>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <div className="rounded-2xl border border-white/8 bg-black/30 p-4">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">This Week</p>
                      <p className="mt-2 text-xl font-semibold text-white">
                        {formatDistance(data.runTrend.thisWeekDistanceMeters)}
                      </p>
                    </div>
                    <div className="rounded-2xl border border-white/8 bg-black/30 p-4">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Last Week</p>
                      <p className="mt-2 text-xl font-semibold text-white">
                        {formatDistance(data.runTrend.lastWeekDistanceMeters)}
                      </p>
                    </div>
                  </div>
                </CardContent>
              </Card>

              <Card className="border-white/5 bg-zinc-900/70">
                <CardHeader>
                  <CardTitle className="text-base font-semibold text-white">Device Fleet</CardTitle>
                </CardHeader>
                <CardContent className="grid gap-3 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                    <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Registered</p>
                    <p className="mt-2 text-2xl font-semibold text-white">{data.deviceSummary.totalDevices}</p>
                  </div>
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                    <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Favorites</p>
                    <p className="mt-2 text-2xl font-semibold text-amber-300">{data.deviceSummary.favorites}</p>
                  </div>
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                    <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Monitoring</p>
                    <p className="mt-2 text-2xl font-semibold text-emerald-300">{data.deviceSummary.monitoring}</p>
                  </div>
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                    <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Lost</p>
                    <p className="mt-2 text-2xl font-semibold text-red-300">{data.deviceSummary.lost}</p>
                  </div>
                </CardContent>
              </Card>
            </section>

            <section className="mt-4 grid gap-4 lg:grid-cols-2">
              <DistributionChart
                title="Workout Starts By Weekday"
                data={data.distributions.byWeekday}
                accentClass="bg-gradient-to-r from-cyan-500 to-emerald-400"
              />
              <DistributionChart
                title="Workout Starts By Hour"
                data={data.distributions.byHour}
                accentClass="bg-gradient-to-r from-amber-400 to-orange-500"
              />
            </section>

            <section className="mt-4 grid gap-4 lg:grid-cols-[1.15fr_0.85fr]">
              <Card className="border-white/5 bg-zinc-900/70">
                <CardHeader className="flex flex-row items-center justify-between gap-4">
                  <div>
                    <CardTitle className="text-base font-semibold text-white">Recent Runs</CardTitle>
                    <p className="mt-1 text-sm text-zinc-400">
                      Route-aware drill-downs stay in the dedicated run board, but the browser now exposes the latest capture history here first.
                    </p>
                  </div>
                  <Link to="/runs">
                    <Button variant="outline" className="border-white/10 bg-zinc-950/60 text-zinc-200 hover:bg-zinc-900">
                      Open /runs
                    </Button>
                  </Link>
                </CardHeader>
                <CardContent>
                  {data.recentRuns.length > 0 ? (
                    <div className="grid gap-4 xl:grid-cols-2">
                      {data.recentRuns.map((run) => (
                        <RunGalleryCard key={run._id} run={run} />
                      ))}
                    </div>
                  ) : (
                    <div className="rounded-2xl border border-dashed border-white/10 bg-zinc-950/60 p-8 text-sm text-zinc-400">
                      No runs have synced yet. Capture a route on iOS and the browser gallery will fill in automatically.
                    </div>
                  )}
                </CardContent>
              </Card>

              <Card className="border-white/5 bg-zinc-900/70">
                <CardHeader>
                  <CardTitle className="text-base font-semibold text-white">Run Totals</CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                    <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Lifetime Distance</p>
                    <p className="mt-2 text-2xl font-semibold text-white">
                      {formatDistance(data.runSummary.totalDistanceMeters)}
                    </p>
                  </div>
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                    <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Last 30 Days</p>
                    <p className="mt-2 text-2xl font-semibold text-cyan-300">
                      {formatDistance(data.runSummary.totalDistanceMeters30d)}
                    </p>
                  </div>
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                    <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Avg Run Distance 30d</p>
                    <p className="mt-2 text-2xl font-semibold text-emerald-300">
                      {formatDistance(data.runSummary.averageRunDistanceMeters30d)}
                    </p>
                  </div>
                  <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                    <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Active Runs</p>
                    <p className="mt-2 text-2xl font-semibold text-amber-300">{data.runSummary.activeRuns}</p>
                  </div>
                </CardContent>
              </Card>
            </section>

            <section className="mt-4">
              <Card className="border-white/5 bg-zinc-900/70">
                <CardHeader>
                  <CardTitle className="text-base font-semibold text-white">Device Status</CardTitle>
                </CardHeader>
                <CardContent>
                  {data.devices.length > 0 ? (
                    <div className="grid gap-4 xl:grid-cols-2">
                      {data.devices.map((device) => (
                        <DeviceStatusCard key={device._id} device={device} />
                      ))}
                    </div>
                  ) : (
                    <div className="rounded-2xl border border-dashed border-white/10 bg-zinc-950/60 p-8 text-sm text-zinc-400">
                      No tracked devices yet. Pair gear in the iOS app and the browser will show its latest status and signal history here.
                    </div>
                  )}
                </CardContent>
              </Card>
            </section>

            <section className="mt-4">
              <Card className="border-white/5 bg-zinc-900/70">
                <CardHeader>
                  <CardTitle className="text-base font-semibold text-white">Recent Workouts</CardTitle>
                </CardHeader>
                <CardContent>
                  {data.recentWorkouts.length > 0 ? (
                    <div className="space-y-3">
                      {data.recentWorkouts.map((workout) => (
                        <div
                          key={workout._id}
                          className="grid gap-3 rounded-2xl border border-white/5 bg-zinc-950/70 p-4 md:grid-cols-[1.2fr_0.8fr_0.8fr_0.8fr]"
                        >
                          <div>
                            <p className="font-medium text-white">{workout.name}</p>
                            <p className="mt-1 text-sm text-zinc-400">
                              {formatShortDate(workout.startedAt)}
                              {workout.gymName ? ` • ${workout.gymName}` : ''}
                            </p>
                          </div>
                          <div>
                            <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">Duration</p>
                            <p className="mt-1 text-sm text-zinc-200">{formatMinutes(workout.durationMinutes)}</p>
                          </div>
                          <div>
                            <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">Exercises</p>
                            <p className="mt-1 text-sm text-zinc-200">{workout.exerciseCount}</p>
                          </div>
                          <div>
                            <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">Source</p>
                            <p className="mt-1 text-sm capitalize text-zinc-200">
                              {workout.source.replaceAll('_', ' ')}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="rounded-2xl border border-dashed border-white/10 bg-zinc-950/60 p-8 text-sm text-zinc-400">
                      No completed workouts yet. Finish one on iOS and this page will start filling in immediately.
                    </div>
                  )}
                </CardContent>
              </Card>
            </section>
          </>
        ) : null}
      </main>
      <MedicationDoseDialog
        open={isMedicationDialogOpen}
        onOpenChange={setMedicationDialogOpen}
      />
      <Footer />
    </div>
  );
}
