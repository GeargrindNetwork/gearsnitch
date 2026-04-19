import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';

// ---------------------------------------------------------------------------
// Types (mirror GET /alerts shape built by buildAlertResponse() in
// api/src/modules/alerts/routes.ts — note the API normalizes the legacy
// `disconnect_warning` type to `device_disconnected` on read.)
// ---------------------------------------------------------------------------

type AlertWireType =
  | 'device_disconnected'
  | 'disconnect_warning'
  | 'panic_alarm'
  | 'reconnect_found'
  | 'gym_entry_activate'
  | 'gym_exit_deactivate'
  | string;

type AlertSeverity = 'low' | 'medium' | 'high' | 'critical' | string;

interface AlertEntry {
  _id: string;
  type: AlertWireType;
  severity: AlertSeverity;
  message: string;
  deviceId: string | null;
  deviceName: string | null;
  latitude: number | null;
  longitude: number | null;
  acknowledged: boolean;
  acknowledgedAt: string | null;
  createdAt: string;
}

type AlertCategory = 'disconnect' | 'panic' | 'reconnect' | 'other';
type TypeFilter = 'all' | AlertCategory;
type StatusFilter = 'all' | 'acknowledged' | 'unacknowledged';

const DEFAULT_PAGE_SIZE = 50;

// ---------------------------------------------------------------------------
// Data fetcher / mutator
// ---------------------------------------------------------------------------

async function fetchAlerts(): Promise<AlertEntry[]> {
  const res = await api.get<AlertEntry[]>('/alerts');
  if (!res.success || !res.data) {
    throw new Error(res.error?.message ?? 'Failed to load alerts');
  }
  return res.data;
}

async function acknowledgeAlert(id: string): Promise<void> {
  const res = await api.post<unknown>(`/alerts/${id}/acknowledge`);
  if (!res.success) {
    throw new Error(res.error?.message ?? 'Failed to acknowledge alert');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function categorize(type: AlertWireType): AlertCategory {
  switch (type) {
    case 'device_disconnected':
    case 'disconnect_warning':
      return 'disconnect';
    case 'panic_alarm':
      return 'panic';
    case 'reconnect_found':
      return 'reconnect';
    default:
      return 'other';
  }
}

function typeLabel(type: AlertWireType): string {
  switch (type) {
    case 'device_disconnected':
    case 'disconnect_warning':
      return 'Disconnect';
    case 'panic_alarm':
      return 'Panic';
    case 'reconnect_found':
      return 'Reconnect';
    case 'gym_entry_activate':
      return 'Gym entry';
    case 'gym_exit_deactivate':
      return 'Gym exit';
    default:
      return type.replace(/_/g, ' ');
  }
}

/**
 * Map alert category to a Tailwind class pair (border + text) applied to an
 * outline Badge. Panic uses destructive red, disconnect uses amber,
 * reconnect uses emerald (default/positive), and everything else is muted.
 */
function severityBadgeClass(category: AlertCategory): string {
  switch (category) {
    case 'panic':
      return 'border-rose-700/70 bg-rose-500/10 text-rose-300';
    case 'disconnect':
      return 'border-amber-700/70 bg-amber-500/10 text-amber-300';
    case 'reconnect':
      return 'border-emerald-700/70 bg-emerald-500/10 text-emerald-300';
    default:
      return 'border-zinc-700 bg-zinc-800/40 text-zinc-300';
  }
}

function formatTimestamp(iso: string): string {
  return new Date(iso).toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function AlertsPage() {
  const { isAuthenticated } = useAuth();
  const queryClient = useQueryClient();
  const [typeFilter, setTypeFilter] = useState<TypeFilter>('all');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [visibleCount, setVisibleCount] = useState<number>(DEFAULT_PAGE_SIZE);

  const alertsQuery = useQuery<AlertEntry[]>({
    queryKey: ['alerts', 'list'],
    queryFn: fetchAlerts,
    enabled: isAuthenticated,
    retry: false,
  });

  const ackMutation = useMutation({
    mutationFn: acknowledgeAlert,
    onMutate: async (alertId: string) => {
      await queryClient.cancelQueries({ queryKey: ['alerts', 'list'] });
      const previous = queryClient.getQueryData<AlertEntry[]>(['alerts', 'list']);
      const nowIso = new Date().toISOString();
      queryClient.setQueryData<AlertEntry[]>(['alerts', 'list'], (current) =>
        (current ?? []).map((entry) =>
          entry._id === alertId
            ? { ...entry, acknowledged: true, acknowledgedAt: entry.acknowledgedAt ?? nowIso }
            : entry,
        ),
      );
      return { previous };
    },
    onError: (err, _alertId, context) => {
      if (context?.previous) {
        queryClient.setQueryData(['alerts', 'list'], context.previous);
      }
      toast.error(err instanceof Error ? err.message : 'Failed to acknowledge alert');
    },
    onSuccess: () => {
      toast.success('Alert acknowledged');
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ['alerts', 'list'] });
    },
  });

  const allAlerts = alertsQuery.data ?? [];

  const filteredAlerts = useMemo(() => {
    return allAlerts.filter((alert) => {
      if (typeFilter !== 'all' && categorize(alert.type) !== typeFilter) {
        return false;
      }
      if (statusFilter === 'acknowledged' && !alert.acknowledged) {
        return false;
      }
      if (statusFilter === 'unacknowledged' && alert.acknowledged) {
        return false;
      }
      return true;
    });
  }, [allAlerts, typeFilter, statusFilter]);

  const visibleAlerts = filteredAlerts.slice(0, visibleCount);
  const hasMore = filteredAlerts.length > visibleAlerts.length;

  const unacknowledgedCount = allAlerts.reduce(
    (count, alert) => (alert.acknowledged ? count : count + 1),
    0,
  );

  const setType = (next: TypeFilter) => {
    setTypeFilter(next);
    setVisibleCount(DEFAULT_PAGE_SIZE);
  };

  const setStatus = (next: StatusFilter) => {
    setStatusFilter(next);
    setVisibleCount(DEFAULT_PAGE_SIZE);
  };

  const typeOptions: Array<{ value: TypeFilter; label: string }> = [
    { value: 'all', label: 'All types' },
    { value: 'panic', label: 'Panic' },
    { value: 'disconnect', label: 'Disconnect' },
    { value: 'reconnect', label: 'Reconnect' },
    { value: 'other', label: 'Other' },
  ];

  const statusOptions: Array<{ value: StatusFilter; label: string }> = [
    { value: 'all', label: 'All' },
    { value: 'unacknowledged', label: 'Unacknowledged' },
    { value: 'acknowledged', label: 'Acknowledged' },
  ];

  return (
    <div className="dark min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <main className="mx-auto max-w-4xl space-y-6 px-6 pb-16 pt-28 lg:px-8">
        <section className="space-y-2">
          <Badge
            variant="secondary"
            className="border border-rose-500/20 bg-rose-500/10 text-rose-300"
          >
            Alerts
          </Badge>
          <h1 className="text-3xl font-bold tracking-tight">Alert history</h1>
          <p className="max-w-2xl text-sm text-zinc-400">
            Review disconnect, panic, and reconnect events from your monitored devices.
            Acknowledging an alert marks it as seen but never deletes the record.
          </p>
        </section>

        {alertsQuery.isLoading && (
          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardContent className="py-12 text-center text-zinc-500">
              Loading your alert history...
            </CardContent>
          </Card>
        )}

        {!alertsQuery.isLoading && alertsQuery.error && (
          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardHeader>
              <CardTitle>Alerts unavailable</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-zinc-400">
              <p>
                {alertsQuery.error instanceof Error
                  ? alertsQuery.error.message
                  : 'Failed to load alerts.'}
              </p>
              <p className="text-sm text-zinc-500">
                Try refreshing the page. If the problem persists, sign out and sign back in.
              </p>
            </CardContent>
          </Card>
        )}

        {!alertsQuery.isLoading && !alertsQuery.error && (
          <>
            {/* Summary */}
            <section className="grid gap-4 sm:grid-cols-3">
              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader className="pb-2">
                  <CardTitle className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                    Total
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-3xl font-bold text-white">{allAlerts.length}</p>
                  <p className="text-xs text-zinc-500">last 100 alerts</p>
                </CardContent>
              </Card>

              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader className="pb-2">
                  <CardTitle className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                    Unacknowledged
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-3xl font-bold text-amber-400">{unacknowledgedCount}</p>
                  <p className="text-xs text-zinc-500">need your review</p>
                </CardContent>
              </Card>

              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader className="pb-2">
                  <CardTitle className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                    Showing
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-3xl font-bold text-white">{visibleAlerts.length}</p>
                  <p className="text-xs text-zinc-500">
                    of {filteredAlerts.length} matching filters
                  </p>
                </CardContent>
              </Card>
            </section>

            {/* Filters */}
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardHeader className="pb-3">
                <CardTitle className="text-sm text-zinc-200">Filters</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <p className="mb-2 text-xs uppercase tracking-[0.16em] text-zinc-500">
                    Type
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {typeOptions.map((option) => {
                      const active = typeFilter === option.value;
                      return (
                        <Button
                          key={option.value}
                          size="sm"
                          variant={active ? 'default' : 'outline'}
                          className={
                            active
                              ? 'bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400'
                              : 'border-zinc-700 text-zinc-300 hover:text-white'
                          }
                          onClick={() => setType(option.value)}
                        >
                          {option.label}
                        </Button>
                      );
                    })}
                  </div>
                </div>

                <div>
                  <p className="mb-2 text-xs uppercase tracking-[0.16em] text-zinc-500">
                    Status
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {statusOptions.map((option) => {
                      const active = statusFilter === option.value;
                      return (
                        <Button
                          key={option.value}
                          size="sm"
                          variant={active ? 'default' : 'outline'}
                          className={
                            active
                              ? 'bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400'
                              : 'border-zinc-700 text-zinc-300 hover:text-white'
                          }
                          onClick={() => setStatus(option.value)}
                        >
                          {option.label}
                        </Button>
                      );
                    })}
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* List */}
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardHeader>
                <CardTitle>Recent alerts</CardTitle>
              </CardHeader>
              <CardContent>
                {filteredAlerts.length === 0 ? (
                  <p className="text-sm text-zinc-400">
                    {allAlerts.length === 0
                      ? 'No alerts yet. Connected devices will report disconnects and panic events here.'
                      : 'No alerts match the current filters.'}
                  </p>
                ) : (
                  <ul className="space-y-0">
                    {visibleAlerts.map((alert, index) => {
                      const category = categorize(alert.type);
                      const isAcking =
                        ackMutation.isPending && ackMutation.variables === alert._id;
                      return (
                        <li key={alert._id}>
                          {index > 0 && <Separator className="my-3 bg-zinc-800" />}
                          <div className="flex flex-col gap-3 rounded-lg px-1 py-2 sm:flex-row sm:items-start sm:justify-between">
                            <div className="min-w-0 space-y-1">
                              <div className="flex flex-wrap items-center gap-2">
                                <Badge
                                  variant="outline"
                                  className={severityBadgeClass(category)}
                                >
                                  {typeLabel(alert.type)}
                                </Badge>
                                {alert.acknowledged ? (
                                  <Badge
                                    variant="outline"
                                    className="border-zinc-700 text-zinc-400"
                                  >
                                    Acknowledged
                                  </Badge>
                                ) : (
                                  <Badge
                                    variant="outline"
                                    className="border-amber-700/70 bg-amber-500/10 text-amber-300"
                                  >
                                    Unacknowledged
                                  </Badge>
                                )}
                                <span className="text-xs text-zinc-500">
                                  {formatTimestamp(alert.createdAt)}
                                </span>
                              </div>

                              <p className="truncate text-sm font-medium text-zinc-100">
                                {alert.deviceName ?? 'Unknown device'}
                              </p>

                              <p className="text-sm text-zinc-300">{alert.message}</p>

                              {alert.acknowledged && alert.acknowledgedAt && (
                                <p className="text-xs text-zinc-500">
                                  Acknowledged {formatTimestamp(alert.acknowledgedAt)}
                                </p>
                              )}
                            </div>

                            <div className="shrink-0 sm:pl-4">
                              {alert.acknowledged ? (
                                <Button
                                  size="sm"
                                  variant="outline"
                                  disabled
                                  className="border-zinc-800 text-zinc-500"
                                >
                                  Acknowledged
                                </Button>
                              ) : (
                                <Button
                                  size="sm"
                                  variant="outline"
                                  className="border-zinc-700 text-zinc-200 hover:text-white"
                                  onClick={() => ackMutation.mutate(alert._id)}
                                  disabled={isAcking}
                                >
                                  {isAcking ? 'Acknowledging…' : 'Acknowledge'}
                                </Button>
                              )}
                            </div>
                          </div>
                        </li>
                      );
                    })}
                  </ul>
                )}

                {hasMore && (
                  <div className="mt-6 flex justify-center">
                    <Button
                      size="sm"
                      variant="outline"
                      className="border-zinc-700 text-zinc-200 hover:text-white"
                      onClick={() => setVisibleCount((current) => current + DEFAULT_PAGE_SIZE)}
                    >
                      Load more
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>
          </>
        )}
      </main>

      <Footer />
    </div>
  );
}
