import { useState } from 'react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import {
  getNotificationHistory,
  type NotificationHistoryItem,
  type NotificationHistoryStatus,
} from '@/lib/api';
import { useAuth } from '@/lib/auth';

// Backlog item #23 — Notifications history page.
// Lists the authenticated user's APNs/push log newest-first, paginated 25/page.
// Backed by `GET /notifications/history` (see api/src/modules/notifications/routes.ts).

const PAGE_SIZE = 25;

function formatTimestamp(iso: string | null): string {
  if (!iso) return '—';
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return '—';
  return parsed.toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function typeLabel(type: string): string {
  // Re-use the raw type but make snake_case human-readable.
  return type.replace(/_/g, ' ');
}

function statusBadgeClass(status: NotificationHistoryStatus): string {
  switch (status) {
    case 'delivered':
      return 'border-emerald-700/70 bg-emerald-500/10 text-emerald-300';
    case 'read':
      return 'border-cyan-700/70 bg-cyan-500/10 text-cyan-300';
    case 'failed':
      return 'border-rose-700/70 bg-rose-500/10 text-rose-300';
    case 'sent':
    default:
      return 'border-zinc-700 bg-zinc-800/40 text-zinc-300';
  }
}

function statusLabel(status: NotificationHistoryStatus): string {
  switch (status) {
    case 'delivered':
      return 'Delivered';
    case 'read':
      return 'Read';
    case 'failed':
      return 'Failed';
    case 'sent':
    default:
      return 'Sent';
  }
}

function RowSkeleton() {
  return (
    <li className="animate-pulse rounded-lg border border-zinc-800 bg-zinc-950 p-4">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 space-y-2">
          <div className="h-3 w-24 rounded bg-zinc-800" />
          <div className="h-4 w-48 rounded bg-zinc-800" />
          <div className="h-3 w-72 rounded bg-zinc-800" />
        </div>
        <div className="h-5 w-16 rounded-full bg-zinc-800" />
      </div>
    </li>
  );
}

function NotificationRow({ item }: { item: NotificationHistoryItem }) {
  return (
    <li className="rounded-lg border border-zinc-800 bg-zinc-950 p-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="outline" className="border-zinc-700 text-zinc-300">
              {typeLabel(item.notificationType)}
            </Badge>
            <span className="text-xs text-zinc-500">{formatTimestamp(item.sentAt)}</span>
          </div>
          {item.title && (
            <p className="truncate text-sm font-medium text-zinc-100">{item.title}</p>
          )}
          {item.body && <p className="text-sm text-zinc-300">{item.body}</p>}
          {item.failureReason && (
            <p className="text-xs text-rose-300/80">Failure: {item.failureReason}</p>
          )}
        </div>
        <div className="shrink-0 sm:pl-4">
          <Badge variant="outline" className={statusBadgeClass(item.status)}>
            {statusLabel(item.status)}
          </Badge>
        </div>
      </div>
    </li>
  );
}

export default function NotificationsPage() {
  // `RequireAuth` at the route layer guards unauthenticated access. We still
  // gate the query on `isAuthenticated` to avoid firing while the auth
  // context is bootstrapping (mirrors BillingHistoryPage).
  const { isAuthenticated } = useAuth();
  const [page, setPage] = useState(1);

  const query = useQuery({
    queryKey: ['notifications-history', page],
    queryFn: () => getNotificationHistory({ page, limit: PAGE_SIZE }),
    enabled: isAuthenticated,
    placeholderData: keepPreviousData,
    retry: false,
    staleTime: 30_000,
  });

  const data = query.data;
  const items = data?.items ?? [];
  const totalPages = data?.totalPages ?? 0;
  const total = data?.total ?? 0;
  const isEmpty = !query.isLoading && !query.isError && items.length === 0 && page === 1;
  const canPrev = page > 1;
  const canNext = totalPages > 0 ? page < totalPages : items.length === PAGE_SIZE;

  return (
    <div className="dark min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <section className="px-6 py-16 pt-24 lg:px-8">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6">
            <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">
              <Link to="/account" className="hover:text-zinc-300">Account</Link>
              <span className="mx-2 text-zinc-700">/</span>
              <span className="text-zinc-400">Notifications</span>
            </p>
            <h1 className="mt-2 text-3xl font-bold tracking-tight">Notifications</h1>
            <p className="mt-2 text-sm text-zinc-400">
              Every push notification we've sent to your devices, newest first.
              {total > 0 && (
                <> {total} total record{total === 1 ? '' : 's'}.</>
              )}
            </p>
          </div>

          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardHeader>
              <CardTitle>Push history</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {query.isLoading && (
                <ul className="space-y-3">
                  <RowSkeleton />
                  <RowSkeleton />
                  <RowSkeleton />
                </ul>
              )}

              {query.isError && !query.isLoading && (
                <div className="rounded-lg border border-rose-900/60 bg-rose-950/20 p-4 text-sm text-rose-200">
                  <p className="font-medium">Couldn't load your notifications.</p>
                  <p className="mt-1 text-rose-300/80">
                    {query.error instanceof Error
                      ? query.error.message
                      : 'Please try again in a moment.'}
                  </p>
                  <Button
                    size="sm"
                    variant="outline"
                    className="mt-3 border-rose-800 text-rose-200 hover:text-white"
                    onClick={() => query.refetch()}
                  >
                    Retry
                  </Button>
                </div>
              )}

              {isEmpty && (
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-6 text-center">
                  <p className="text-sm font-medium text-zinc-200">No notifications yet</p>
                  <p className="mt-2 text-sm text-zinc-400">
                    Push notifications we send to your iPhone or Apple Watch will
                    show up here once they're sent.
                  </p>
                </div>
              )}

              {!query.isLoading && !query.isError && items.length > 0 && (
                <ul className="space-y-3">
                  {items.map((item) => (
                    <NotificationRow key={item.id} item={item} />
                  ))}
                </ul>
              )}

              {(canPrev || canNext) && !query.isError && (
                <div className="flex items-center justify-between pt-4">
                  <Button
                    size="sm"
                    variant="outline"
                    className="border-zinc-700 text-zinc-200 hover:text-white"
                    onClick={() => setPage((current) => Math.max(1, current - 1))}
                    disabled={!canPrev || query.isFetching}
                  >
                    ← Prev
                  </Button>
                  <span className="text-xs text-zinc-500">
                    Page {page}
                    {totalPages > 0 ? ` of ${totalPages}` : ''}
                  </span>
                  <Button
                    size="sm"
                    variant="outline"
                    className="border-zinc-700 text-zinc-200 hover:text-white"
                    onClick={() => setPage((current) => current + 1)}
                    disabled={!canNext || query.isFetching}
                  >
                    Next →
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </section>

      <Footer />
    </div>
  );
}
