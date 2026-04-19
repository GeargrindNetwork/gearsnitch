import { useEffect, useMemo, useState } from 'react';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

const API_BASE = (import.meta.env.VITE_API_URL as string | undefined) ||
  'http://localhost:3001/api/v1';

// Strip the "/api/v1" suffix (if present) to derive the bare origin used by
// non-versioned routes (e.g., the realtime websocket health endpoint).
const API_ORIGIN = API_BASE.replace(/\/api\/v1\/?$/, '');

const REFRESH_INTERVAL_MS = 30_000;

type HealthState = 'operational' | 'degraded' | 'down' | 'unknown';

type ServiceDef = {
  id: string;
  name: string;
  description: string;
  url: string;
  // Some endpoints may not exist yet; a 404 should render "Unknown" rather
  // than "Down" so the page isn't alarmist while routes are being added.
  treat404AsUnknown?: boolean;
};

type ServiceResult = {
  state: HealthState;
  checkedAt: number;
  latencyMs: number | null;
  detail: string;
};

const SERVICES: ServiceDef[] = [
  {
    id: 'api',
    name: 'API',
    description: 'Core REST API (auth, subscriptions, labs, store).',
    url: `${API_BASE}/health`,
  },
  {
    id: 'web',
    name: 'Web',
    description: 'gearsnitch.com marketing + account site.',
    // Self-check: any 2xx from the current origin means we served this page.
    url: `${window.location.origin}/`,
  },
  {
    id: 'realtime',
    name: 'Realtime WS',
    description: 'Websocket gateway for live device + workout streams.',
    url: `${API_ORIGIN}/realtime/health`,
    treat404AsUnknown: true,
  },
  {
    id: 'worker',
    name: 'Worker',
    description: 'Background jobs (notifications, reconciliation, lab polling).',
    url: `${API_BASE}/worker/health`,
    treat404AsUnknown: true,
  },
];

async function checkService(svc: ServiceDef): Promise<ServiceResult> {
  const startedAt = performance.now();
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8_000);
    const res = await fetch(svc.url, {
      method: 'GET',
      signal: controller.signal,
      credentials: 'omit',
      cache: 'no-store',
    });
    clearTimeout(timeout);
    const latencyMs = Math.round(performance.now() - startedAt);

    if (res.status === 404 && svc.treat404AsUnknown) {
      return {
        state: 'unknown',
        checkedAt: Date.now(),
        latencyMs,
        detail: 'Endpoint not deployed yet (404).',
      };
    }
    if (res.ok) {
      return {
        state: 'operational',
        checkedAt: Date.now(),
        latencyMs,
        detail: `HTTP ${res.status} in ${latencyMs}ms`,
      };
    }
    if (res.status >= 500) {
      return {
        state: 'down',
        checkedAt: Date.now(),
        latencyMs,
        detail: `HTTP ${res.status}`,
      };
    }
    return {
      state: 'degraded',
      checkedAt: Date.now(),
      latencyMs,
      detail: `HTTP ${res.status}`,
    };
  } catch (err) {
    return {
      state: 'down',
      checkedAt: Date.now(),
      latencyMs: null,
      detail: err instanceof Error ? err.message : 'Network error',
    };
  }
}

function formatTimestamp(ms: number): string {
  try {
    return new Date(ms).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  } catch {
    return new Date(ms).toISOString();
  }
}

function StatusDot({ state }: { state: HealthState }) {
  const styles: Record<HealthState, string> = {
    operational: 'bg-emerald-400 shadow-[0_0_12px_rgba(52,211,153,0.6)]',
    degraded: 'bg-amber-400 shadow-[0_0_12px_rgba(251,191,36,0.6)]',
    down: 'bg-rose-500 shadow-[0_0_12px_rgba(244,63,94,0.6)]',
    unknown: 'bg-zinc-500',
  };
  const labels: Record<HealthState, string> = {
    operational: 'Operational',
    degraded: 'Degraded',
    down: 'Down',
    unknown: 'Unknown',
  };
  return (
    <span className="inline-flex items-center gap-2">
      <span
        aria-hidden="true"
        className={`inline-block h-2.5 w-2.5 rounded-full ${styles[state]}`}
      />
      <span className="text-xs font-medium uppercase tracking-wider text-zinc-400">
        {labels[state]}
      </span>
    </span>
  );
}

function overallState(results: Record<string, ServiceResult | undefined>): {
  state: HealthState;
  label: string;
} {
  const known = SERVICES
    .map((s) => results[s.id]?.state)
    .filter((v): v is HealthState => Boolean(v));

  if (known.length === 0) {
    return { state: 'unknown', label: 'Checking systems…' };
  }
  const downCount = known.filter((s) => s === 'down').length;
  const degradedCount = known.filter((s) => s === 'degraded').length;

  if (downCount >= 2) {
    return { state: 'down', label: 'Major outage' };
  }
  if (downCount === 1 || degradedCount > 0) {
    return { state: 'degraded', label: 'Partial outage' };
  }
  // Only operational and/or unknown remain — treat as operational overall.
  return { state: 'operational', label: 'All systems operational' };
}

export default function StatusPage() {
  const [results, setResults] = useState<Record<string, ServiceResult>>({});
  const [lastRefresh, setLastRefresh] = useState<number | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function refresh() {
      setIsRefreshing(true);
      const entries = await Promise.all(
        SERVICES.map(async (svc) => [svc.id, await checkService(svc)] as const),
      );
      if (cancelled) return;
      setResults(Object.fromEntries(entries));
      setLastRefresh(Date.now());
      setIsRefreshing(false);
    }

    void refresh();
    const interval = window.setInterval(refresh, REFRESH_INTERVAL_MS);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, []);

  const overall = useMemo(() => overallState(results), [results]);

  const overallBadgeStyles: Record<HealthState, string> = {
    operational: 'border-emerald-400/30 bg-emerald-400/10 text-emerald-300',
    degraded: 'border-amber-400/30 bg-amber-400/10 text-amber-200',
    down: 'border-rose-500/30 bg-rose-500/10 text-rose-300',
    unknown: 'border-zinc-600 bg-zinc-800/50 text-zinc-300',
  };

  return (
    <div className="dark min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight text-white">
              System Status
            </h1>
            <p className="mt-2 text-sm text-zinc-500">
              Live health of GearSnitch services. Auto-refreshes every 30
              seconds.
            </p>
          </div>
          <span
            className={`inline-flex items-center gap-2 self-start rounded-full border px-4 py-1.5 text-sm font-medium ${overallBadgeStyles[overall.state]}`}
            role="status"
            aria-live="polite"
          >
            <StatusDot state={overall.state} />
            <span>{overall.label}</span>
          </span>
        </div>

        <Separator className="my-8 bg-white/5" />

        <div className="grid gap-4 sm:grid-cols-2">
          {SERVICES.map((svc) => {
            const result = results[svc.id];
            const state: HealthState = result?.state ?? 'unknown';
            return (
              <Card
                key={svc.id}
                className="border-0 bg-zinc-900/60 ring-white/5"
              >
                <CardHeader className="flex flex-row items-start justify-between gap-3 space-y-0">
                  <div>
                    <CardTitle className="text-base text-white">
                      {svc.name}
                    </CardTitle>
                    <p className="mt-1 text-xs leading-relaxed text-zinc-500">
                      {svc.description}
                    </p>
                  </div>
                  <StatusDot state={state} />
                </CardHeader>
                <CardContent className="space-y-1 text-xs text-zinc-500">
                  <p>
                    <span className="text-zinc-400">Last check:</span>{' '}
                    {result ? formatTimestamp(result.checkedAt) : '—'}
                  </p>
                  <p className="truncate">
                    <span className="text-zinc-400">Detail:</span>{' '}
                    {result?.detail ?? 'Pending first check…'}
                  </p>
                </CardContent>
              </Card>
            );
          })}
        </div>

        <Separator className="my-8 bg-white/5" />

        <section className="space-y-2 text-xs text-zinc-500">
          <p>
            <span className="text-zinc-400">Last refreshed:</span>{' '}
            {lastRefresh ? formatTimestamp(lastRefresh) : 'never'}
            {isRefreshing ? ' · refreshing…' : ''}
          </p>
          <p>
            Need help? Email{' '}
            <a
              href="mailto:support@gearsnitch.com"
              className="text-cyan-400 underline hover:text-cyan-300"
            >
              support@gearsnitch.com
            </a>
            .
          </p>
        </section>
      </main>

      <Footer />
    </div>
  );
}
