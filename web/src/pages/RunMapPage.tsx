import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import RunRoutePreview, {
  type RouteBounds,
  type RoutePoint,
} from '@/components/runs/RunRoutePreview';
import { api } from '@/lib/api';

interface RunRoutePayload {
  pointCount: number;
  bounds: RouteBounds | null;
  points?: RoutePoint[];
}

interface RunApiRecord {
  _id: string;
  startedAt: string;
  endedAt: string | null;
  status: 'active' | 'completed';
  durationSeconds: number;
  durationMinutes: number;
  distanceMeters: number;
  averagePaceSecondsPerKm: number | null;
  source: string | null;
  notes: string | null;
  route: RunRoutePayload;
  createdAt?: string;
  updatedAt?: string;
}

interface RunRecord {
  id: string;
  startedAt: string;
  endedAt: string | null;
  status: 'active' | 'completed';
  durationSeconds: number;
  durationMinutes: number;
  distanceMeters: number;
  averagePaceSecondsPerKm: number | null;
  source: string | null;
  notes: string | null;
  route: RunRoutePayload;
  createdAt?: string;
  updatedAt?: string;
}

function normalizeRun(run: RunApiRecord): RunRecord {
  return {
    id: run._id,
    startedAt: run.startedAt,
    endedAt: run.endedAt,
    status: run.status,
    durationSeconds: run.durationSeconds,
    durationMinutes: run.durationMinutes,
    distanceMeters: run.distanceMeters,
    averagePaceSecondsPerKm: run.averagePaceSecondsPerKm,
    source: run.source,
    notes: run.notes,
    route: run.route,
    createdAt: run.createdAt,
    updatedAt: run.updatedAt,
  };
}

async function fetchRuns(): Promise<RunRecord[]> {
  const response = await api.get<RunApiRecord[]>('/runs?limit=24');
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load runs');
  }

  return response.data.map(normalizeRun);
}

async function fetchActiveRun(): Promise<RunRecord | null> {
  const response = await api.get<RunApiRecord | null>('/runs/active');
  if (!response.success) {
    throw new Error(response.error?.message || 'Failed to load active run');
  }

  return response.data ? normalizeRun(response.data) : null;
}

async function fetchRunDetail(id: string): Promise<RunRecord> {
  const response = await api.get<RunApiRecord>(`/runs/${id}`);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load run details');
  }

  return normalizeRun(response.data);
}

function formatDistance(distanceMeters: number) {
  const distanceKm = distanceMeters / 1000;
  return distanceKm >= 10 ? `${distanceKm.toFixed(1)} km` : `${distanceKm.toFixed(2)} km`;
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

function formatPace(secondsPerKm: number | null) {
  if (!secondsPerKm) {
    return '--:-- /km';
  }

  const minutes = Math.floor(secondsPerKm / 60);
  const seconds = secondsPerKm % 60;
  return `${minutes}:${String(seconds).padStart(2, '0')} /km`;
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(value));
}

function formatRelativeDate(value: string) {
  return new Intl.DateTimeFormat('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  }).format(new Date(value));
}

function SummaryCard({
  label,
  value,
  accentClass,
}: {
  label: string;
  value: string;
  accentClass: string;
}) {
  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardContent className="flex flex-col gap-2 p-5">
        <span className="text-xs font-medium uppercase tracking-[0.18em] text-zinc-500">{label}</span>
        <span className={`text-3xl font-semibold ${accentClass}`}>{value}</span>
      </CardContent>
    </Card>
  );
}

export default function RunMapPage() {
  const [preferredRunId, setPreferredRunId] = useState<string | null>(null);

  const {
    data: runs = [],
    isLoading: isLoadingRuns,
    error: runsError,
    refetch: refetchRuns,
    isFetching: isFetchingRuns,
  } = useQuery({
    queryKey: ['runs', 'history'],
    queryFn: fetchRuns,
    staleTime: 30_000,
  });

  const {
    data: activeRun,
    error: activeRunError,
    refetch: refetchActiveRun,
  } = useQuery({
    queryKey: ['runs', 'active'],
    queryFn: fetchActiveRun,
    staleTime: 15_000,
  });

  const visibleRuns = useMemo(
    () => runs.filter((run) => run.id !== activeRun?.id),
    [activeRun?.id, runs],
  );

  const availableRunIds = useMemo(
    () => new Set([...(activeRun ? [activeRun.id] : []), ...visibleRuns.map((run) => run.id)]),
    [activeRun, visibleRuns],
  );

  const selectedRunId = useMemo(() => {
    if (preferredRunId && availableRunIds.has(preferredRunId)) {
      return preferredRunId;
    }

    return activeRun?.id ?? visibleRuns[0]?.id ?? null;
  }, [activeRun?.id, availableRunIds, preferredRunId, visibleRuns]);

  const {
    data: selectedRunDetail,
    isFetching: isFetchingDetail,
  } = useQuery({
    queryKey: ['runs', 'detail', selectedRunId],
    queryFn: () => fetchRunDetail(selectedRunId as string),
    enabled: Boolean(selectedRunId) && selectedRunId !== activeRun?.id,
    staleTime: 30_000,
  });

  const selectedRun = useMemo(() => {
    if (!selectedRunId) {
      return null;
    }

    if (selectedRunId === activeRun?.id) {
      return activeRun;
    }

    return selectedRunDetail ?? visibleRuns.find((run) => run.id === selectedRunId) ?? null;
  }, [activeRun, selectedRunDetail, selectedRunId, visibleRuns]);

  const totalDistanceMeters = useMemo(
    () => visibleRuns.reduce((total, run) => total + run.distanceMeters, 0),
    [visibleRuns],
  );

  const totalDurationSeconds = useMemo(
    () => visibleRuns.reduce((total, run) => total + run.durationSeconds, 0),
    [visibleRuns],
  );

  const pageError = (runsError as Error | null) ?? (activeRunError as Error | null) ?? null;

  return (
    <div className="min-h-screen bg-black text-white">
      <Header />
      <main className="mx-auto flex min-h-screen max-w-7xl flex-col px-4 pb-16 pt-28 sm:px-6 lg:px-8">
        <section className="relative overflow-hidden rounded-[2rem] border border-white/5 bg-zinc-900/70 px-6 py-8 sm:px-8 lg:px-10">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,_rgba(34,211,238,0.16),_transparent_32%),radial-gradient(circle_at_bottom_right,_rgba(16,185,129,0.14),_transparent_35%)]" />
          <div className="relative max-w-3xl">
            <Badge variant="secondary" className="border border-cyan-500/20 bg-cyan-500/10 text-cyan-400">
              Outdoor Runs
            </Badge>
            <h1 className="mt-4 text-4xl font-bold tracking-tight text-white sm:text-5xl">
              Route capture, pace, and finish state without opening Xcode or the API logs.
            </h1>
            <p className="mt-4 max-w-2xl text-base leading-7 text-zinc-400 sm:text-lg">
              This view reads the same run records the iOS tracker now writes. Active sessions stay visible,
              completed efforts keep their captured path, and the browser gets a fast route replay with no third-party map dependency.
            </p>
          </div>
        </section>

        <section className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <SummaryCard
            label="Active Session"
            value={activeRun ? 'Live' : 'None'}
            accentClass={activeRun ? 'text-amber-300' : 'text-zinc-200'}
          />
          <SummaryCard
            label="Completed Runs"
            value={String(visibleRuns.length)}
            accentClass="text-cyan-400"
          />
          <SummaryCard
            label="Tracked Distance"
            value={formatDistance(totalDistanceMeters)}
            accentClass="text-emerald-400"
          />
          <SummaryCard
            label="Recorded Duration"
            value={formatDuration(totalDurationSeconds)}
            accentClass="text-lime-300"
          />
        </section>

        {pageError ? (
          <Card className="mt-6 border-red-500/20 bg-red-500/5">
            <CardContent className="flex flex-col gap-4 p-6 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-base font-semibold text-white">Run data unavailable</p>
                <p className="mt-1 text-sm text-zinc-300">
                  {pageError.message || 'Refresh the page or sign in again to reload your route history.'}
                </p>
              </div>
              <Button
                className="bg-white text-black hover:bg-zinc-200"
                onClick={() => {
                  void refetchRuns();
                  void refetchActiveRun();
                }}
                disabled={isFetchingRuns}
              >
                {isFetchingRuns ? 'Retrying...' : 'Retry'}
              </Button>
            </CardContent>
          </Card>
        ) : null}

        {activeRun ? (
          <Card className="mt-6 border-amber-500/20 bg-amber-500/5">
            <CardContent className="grid gap-4 p-6 lg:grid-cols-[minmax(0,1fr)_220px] lg:items-center">
              <div>
                <div className="flex items-center gap-2">
                  <span className="inline-flex h-2.5 w-2.5 rounded-full bg-amber-400 shadow-[0_0_18px_rgba(251,191,36,0.8)]" />
                  <p className="text-sm font-semibold uppercase tracking-[0.2em] text-amber-300">Run in progress</p>
                </div>
                <p className="mt-3 text-2xl font-semibold text-white">
                  Started {formatDateTime(activeRun.startedAt)}
                </p>
                <p className="mt-2 max-w-2xl text-sm text-zinc-300">
                  The iOS tracker has an active run open right now. Select it from the list to inspect its current route points and partial pacing.
                </p>
              </div>
              <div className="grid grid-cols-2 gap-3 rounded-3xl border border-white/8 bg-black/40 p-4">
                <div>
                  <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Distance</p>
                  <p className="mt-2 text-xl font-semibold text-white">{formatDistance(activeRun.distanceMeters)}</p>
                </div>
                <div>
                  <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Pace</p>
                  <p className="mt-2 text-xl font-semibold text-white">{formatPace(activeRun.averagePaceSecondsPerKm)}</p>
                </div>
              </div>
            </CardContent>
          </Card>
        ) : null}

        <section className="mt-6 grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]">
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="flex flex-row items-center justify-between gap-4">
              <div>
                <CardTitle className="text-lg font-semibold text-white">Recent Runs</CardTitle>
                <p className="mt-1 text-sm text-zinc-400">Select a record to load its full route detail.</p>
              </div>
              <Button
                variant="outline"
                className="border-white/10 bg-zinc-950/60 text-zinc-200 hover:bg-zinc-900"
                onClick={() => {
                  void refetchRuns();
                  void refetchActiveRun();
                }}
                disabled={isFetchingRuns}
              >
                Refresh
              </Button>
            </CardHeader>
            <CardContent className="space-y-3">
              {isLoadingRuns ? (
                <div className="rounded-3xl border border-white/8 bg-black/30 p-5 text-sm text-zinc-400">
                  Loading route history...
                </div>
              ) : null}

              {!isLoadingRuns && !activeRun && visibleRuns.length === 0 ? (
                <div className="rounded-3xl border border-white/8 bg-black/30 p-5 text-sm text-zinc-400">
                  No runs have been recorded yet. Start one on iOS and the route history will show up here.
                </div>
              ) : null}

              {activeRun ? (
                <button
                  type="button"
                  onClick={() => setPreferredRunId(activeRun.id)}
                  className={`w-full rounded-3xl border px-4 py-4 text-left transition ${
                    selectedRunId === activeRun.id
                      ? 'border-amber-400/40 bg-amber-400/10 shadow-[0_0_0_1px_rgba(251,191,36,0.15)]'
                      : 'border-white/8 bg-black/30 hover:border-white/15 hover:bg-black/45'
                  }`}
                >
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <p className="text-sm font-semibold text-white">Active run</p>
                      <p className="mt-1 text-xs text-zinc-400">{formatRelativeDate(activeRun.startedAt)}</p>
                    </div>
                    <Badge className="border border-amber-400/20 bg-amber-400/10 text-amber-300">Live</Badge>
                  </div>
                  <div className="mt-4 flex items-center gap-4 text-sm text-zinc-300">
                    <span>{formatDistance(activeRun.distanceMeters)}</span>
                    <span>{formatPace(activeRun.averagePaceSecondsPerKm)}</span>
                  </div>
                </button>
              ) : null}

              {visibleRuns.map((run) => (
                <button
                  key={run.id}
                  type="button"
                  onClick={() => setPreferredRunId(run.id)}
                  className={`w-full rounded-3xl border px-4 py-4 text-left transition ${
                    selectedRunId === run.id
                      ? 'border-cyan-400/35 bg-cyan-400/8 shadow-[0_0_0_1px_rgba(34,211,238,0.12)]'
                      : 'border-white/8 bg-black/30 hover:border-white/15 hover:bg-black/45'
                  }`}
                >
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <p className="text-sm font-semibold text-white">{formatRelativeDate(run.startedAt)}</p>
                      <p className="mt-1 text-xs text-zinc-400">{formatDateTime(run.startedAt)}</p>
                    </div>
                    <Badge variant="outline" className="border-white/10 text-zinc-300">
                      {run.source ?? 'ios'}
                    </Badge>
                  </div>
                  <div className="mt-4 grid grid-cols-3 gap-3 text-sm text-zinc-300">
                    <span>{formatDistance(run.distanceMeters)}</span>
                    <span>{formatDuration(run.durationSeconds)}</span>
                    <span>{formatPace(run.averagePaceSecondsPerKm)}</span>
                  </div>
                </button>
              ))}
            </CardContent>
          </Card>

          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader>
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <CardTitle className="text-lg font-semibold text-white">
                    {selectedRun ? (selectedRun.status === 'active' ? 'Active Route' : 'Route Detail') : 'Route Detail'}
                  </CardTitle>
                  <p className="mt-1 text-sm text-zinc-400">
                    {selectedRun
                      ? `Started ${formatDateTime(selectedRun.startedAt)}`
                      : 'Pick a run from the left to load its route and timing data.'}
                  </p>
                </div>
                {selectedRun ? (
                  <Badge
                    className={
                      selectedRun.status === 'active'
                        ? 'border border-amber-400/20 bg-amber-400/10 text-amber-300'
                        : 'border border-emerald-400/20 bg-emerald-400/10 text-emerald-300'
                    }
                  >
                    {selectedRun.status}
                  </Badge>
                ) : null}
              </div>
            </CardHeader>
            <CardContent>
              {!selectedRun ? (
                <div className="rounded-3xl border border-white/8 bg-black/30 p-6 text-sm text-zinc-400">
                  Route detail will populate here once a run is selected.
                </div>
              ) : (
                <div className="space-y-5">
                  <RunRoutePreview
                    points={selectedRun.route.points}
                    bounds={selectedRun.route.bounds}
                    status={selectedRun.status}
                  />

                  {selectedRun.status !== 'active' && isFetchingDetail && !selectedRun.route.points?.length ? (
                    <div className="rounded-2xl border border-white/8 bg-black/30 px-4 py-3 text-sm text-zinc-400">
                      Loading full route geometry...
                    </div>
                  ) : null}

                  <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
                    <div className="rounded-3xl border border-white/8 bg-black/30 p-4">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Distance</p>
                      <p className="mt-2 text-2xl font-semibold text-white">{formatDistance(selectedRun.distanceMeters)}</p>
                    </div>
                    <div className="rounded-3xl border border-white/8 bg-black/30 p-4">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Duration</p>
                      <p className="mt-2 text-2xl font-semibold text-white">{formatDuration(selectedRun.durationSeconds)}</p>
                    </div>
                    <div className="rounded-3xl border border-white/8 bg-black/30 p-4">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Average Pace</p>
                      <p className="mt-2 text-2xl font-semibold text-white">{formatPace(selectedRun.averagePaceSecondsPerKm)}</p>
                    </div>
                    <div className="rounded-3xl border border-white/8 bg-black/30 p-4">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Route Points</p>
                      <p className="mt-2 text-2xl font-semibold text-white">{selectedRun.route.pointCount}</p>
                    </div>
                  </div>

                  <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_280px]">
                    <div className="rounded-3xl border border-white/8 bg-black/30 p-5">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Session Window</p>
                      <div className="mt-4 grid gap-4 sm:grid-cols-2">
                        <div>
                          <p className="text-xs text-zinc-500">Started</p>
                          <p className="mt-2 text-sm font-medium text-white">{formatDateTime(selectedRun.startedAt)}</p>
                        </div>
                        <div>
                          <p className="text-xs text-zinc-500">Ended</p>
                          <p className="mt-2 text-sm font-medium text-white">
                            {selectedRun.endedAt ? formatDateTime(selectedRun.endedAt) : 'Still in progress'}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div className="rounded-3xl border border-white/8 bg-black/30 p-5">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Capture Metadata</p>
                      <div className="mt-4 space-y-3 text-sm text-zinc-300">
                        <div className="flex items-center justify-between gap-3">
                          <span className="text-zinc-500">Source</span>
                          <span>{selectedRun.source ?? 'ios'}</span>
                        </div>
                        <div className="flex items-center justify-between gap-3">
                          <span className="text-zinc-500">Status</span>
                          <span className="capitalize">{selectedRun.status}</span>
                        </div>
                        <div className="flex items-center justify-between gap-3">
                          <span className="text-zinc-500">Bounds</span>
                          <span>{selectedRun.route.bounds ? 'Present' : 'Pending'}</span>
                        </div>
                      </div>
                    </div>
                  </div>

                  {selectedRun.notes ? (
                    <div className="rounded-3xl border border-white/8 bg-black/30 p-5">
                      <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Notes</p>
                      <p className="mt-3 text-sm leading-7 text-zinc-300">{selectedRun.notes}</p>
                    </div>
                  ) : null}
                </div>
              )}
            </CardContent>
          </Card>
        </section>
      </main>
      <Footer />
    </div>
  );
}
