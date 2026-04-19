import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import {
  getSubscriptionInvoices,
  type SubscriptionInvoice,
  type SubscriptionInvoiceStatus,
} from '@/lib/api';
import { useAuth } from '@/lib/auth';

// ---------------------------------------------------------------------------
// Formatters
// ---------------------------------------------------------------------------

function formatInvoiceDate(iso: string | null): string {
  if (!iso) return '—';
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return '—';
  return parsed.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function formatInvoiceAmount(cents: number, currency: string): string {
  const code = (currency || 'usd').toUpperCase();
  const dollars = cents / 100;
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: code,
    }).format(dollars);
  } catch {
    return `$${dollars.toFixed(2)}`;
  }
}

function statusBadgeClass(status: SubscriptionInvoiceStatus): string {
  switch (status) {
    case 'paid':
      return 'border-emerald-700 text-emerald-400';
    case 'open':
      return 'border-amber-700 text-amber-300';
    case 'uncollectible':
      return 'border-rose-700 text-rose-400';
    case 'void':
      return 'border-zinc-700 text-zinc-400';
    case 'draft':
    default:
      return 'border-zinc-700 text-zinc-400';
  }
}

function statusLabel(status: SubscriptionInvoiceStatus): string {
  switch (status) {
    case 'paid': return 'Paid';
    case 'open': return 'Due';
    case 'uncollectible': return 'Failed';
    case 'void': return 'Void';
    case 'draft': return 'Draft';
    default: return status;
  }
}

function describeInvoice(invoice: SubscriptionInvoice): string {
  if (invoice.description && invoice.description.trim().length > 0) {
    return invoice.description;
  }
  if (invoice.periodStart && invoice.periodEnd) {
    return `Subscription • ${formatInvoiceDate(invoice.periodStart)} → ${formatInvoiceDate(
      invoice.periodEnd,
    )}`;
  }
  return 'Subscription billing';
}

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

function InvoiceRowSkeleton() {
  return (
    <div className="animate-pulse rounded-lg border border-zinc-800 bg-zinc-950 p-4">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 space-y-2">
          <div className="h-3 w-28 rounded bg-zinc-800" />
          <div className="h-3 w-64 rounded bg-zinc-800" />
        </div>
        <div className="flex flex-col items-end gap-2">
          <div className="h-3 w-16 rounded bg-zinc-800" />
          <div className="h-5 w-14 rounded-full bg-zinc-800" />
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function BillingHistoryPage() {
  // `RequireAuth` at the route layer gates unauthenticated access. We still
  // pull `isAuthenticated` here to ensure the query stays disabled while the
  // auth context is bootstrapping, mirroring AccountPage's pattern.
  const { isAuthenticated } = useAuth();

  const { data, isLoading, isError, error, refetch, isFetching } = useQuery({
    queryKey: ['subscription-invoices'],
    queryFn: () => getSubscriptionInvoices(),
    enabled: isAuthenticated,
    retry: false,
    staleTime: 60_000,
  });

  useEffect(() => {
    if (isError) {
      toast.error(
        error instanceof Error ? error.message : 'Failed to load billing history',
      );
    }
  }, [isError, error]);

  const invoices = data?.invoices ?? [];
  const isEmpty = !isLoading && !isError && invoices.length === 0;

  return (
    <div className="dark min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <section className="px-6 py-16 pt-24 lg:px-8">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="text-xs uppercase tracking-[0.18em] text-zinc-500">
                <Link to="/account" className="hover:text-zinc-300">Account</Link>
                <span className="mx-2 text-zinc-700">/</span>
                <span className="text-zinc-400">Billing</span>
              </p>
              <h1 className="mt-2 text-3xl font-bold tracking-tight">Billing history</h1>
              <p className="mt-2 text-sm text-zinc-400">
                Your Stripe-issued invoices for GearSnitch Pro. Download a PDF for
                your records or view the hosted receipt online.
              </p>
            </div>

            <Button
              variant="outline"
              className="border-zinc-700 text-zinc-200 hover:text-white"
              onClick={() => refetch()}
              disabled={isFetching}
            >
              {isFetching ? 'Refreshing...' : 'Refresh'}
            </Button>
          </div>

          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardHeader>
              <CardTitle>Invoices</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {isLoading && (
                <>
                  <InvoiceRowSkeleton />
                  <InvoiceRowSkeleton />
                  <InvoiceRowSkeleton />
                </>
              )}

              {isError && !isLoading && (
                <div className="rounded-lg border border-rose-900/60 bg-rose-950/20 p-4 text-sm text-rose-200">
                  <p className="font-medium">Couldn't load your billing history.</p>
                  <p className="mt-1 text-rose-300/80">
                    {error instanceof Error ? error.message : 'Please try again in a moment.'}
                  </p>
                  <Button
                    size="sm"
                    variant="outline"
                    className="mt-3 border-rose-800 text-rose-200 hover:text-white"
                    onClick={() => refetch()}
                  >
                    Retry
                  </Button>
                </div>
              )}

              {isEmpty && (
                <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-6 text-center">
                  <p className="text-sm font-medium text-zinc-200">No invoices yet</p>
                  <p className="mt-2 text-sm text-zinc-400">
                    Only web subscribers have invoices here. If you subscribed via
                    the iOS app, manage your billing in{' '}
                    <span className="text-zinc-200">Apple ID Settings → Subscriptions</span>.
                  </p>
                  <div className="mt-4 flex flex-wrap justify-center gap-3">
                    <Link to="/subscribe">
                      <Button
                        size="sm"
                        className="bg-emerald-500 font-semibold text-black hover:bg-emerald-400"
                      >
                        View Pro plans
                      </Button>
                    </Link>
                    <a
                      href="https://apps.apple.com/account/subscriptions"
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <Button
                        size="sm"
                        variant="outline"
                        className="border-zinc-700 text-zinc-200 hover:text-white"
                      >
                        Manage Apple subscription
                      </Button>
                    </a>
                  </div>
                </div>
              )}

              {!isLoading && !isError && invoices.length > 0 && (
                <>
                  {/* Desktop table header — hidden on mobile, rows reflow to cards. */}
                  <div
                    className="hidden gap-4 border-b border-zinc-800 px-4 pb-2 text-xs uppercase tracking-[0.14em] text-zinc-500 md:grid"
                    style={{ gridTemplateColumns: '1.1fr 2fr 1fr 0.8fr 1.1fr' }}
                  >
                    <span>Date</span>
                    <span>Description</span>
                    <span className="text-right">Amount</span>
                    <span>Status</span>
                    <span className="text-right">Actions</span>
                  </div>

                  <ul className="space-y-3">
                    {invoices.map((invoice) => (
                      <li
                        key={invoice.id}
                        className="rounded-lg border border-zinc-800 bg-zinc-950 p-4 md:p-0"
                      >
                        <div
                          className="grid gap-4 md:px-4 md:py-3"
                          style={{ gridTemplateColumns: 'minmax(0, 1fr)' }}
                        >
                          <div
                            className="grid gap-3 md:gap-4"
                            style={{
                              gridTemplateColumns:
                                'minmax(0, 1fr)',
                            }}
                          >
                            <div
                              className="grid gap-3 md:grid-cols-5 md:items-center"
                            >
                              <div>
                                <p className="text-xs uppercase tracking-[0.14em] text-zinc-500 md:hidden">
                                  Date
                                </p>
                                <p className="text-sm font-medium text-white">
                                  {formatInvoiceDate(invoice.createdAt)}
                                </p>
                                {invoice.number && (
                                  <p className="text-xs text-zinc-500">#{invoice.number}</p>
                                )}
                              </div>

                              <div className="md:col-span-2">
                                <p className="text-xs uppercase tracking-[0.14em] text-zinc-500 md:hidden">
                                  Description
                                </p>
                                <p className="text-sm text-zinc-200">
                                  {describeInvoice(invoice)}
                                </p>
                                {invoice.paidAt && (
                                  <p className="text-xs text-zinc-500">
                                    Paid {formatInvoiceDate(invoice.paidAt)}
                                  </p>
                                )}
                              </div>

                              <div className="md:text-right">
                                <p className="text-xs uppercase tracking-[0.14em] text-zinc-500 md:hidden">
                                  Amount
                                </p>
                                <p className="text-sm font-semibold text-white">
                                  {formatInvoiceAmount(
                                    invoice.status === 'paid'
                                      ? invoice.amountPaid || invoice.amountDue
                                      : invoice.amountDue || invoice.amountPaid,
                                    invoice.currency,
                                  )}
                                </p>
                              </div>

                              <div className="flex items-start gap-2 md:items-center md:justify-start">
                                <Badge
                                  variant="outline"
                                  className={statusBadgeClass(invoice.status)}
                                >
                                  {statusLabel(invoice.status)}
                                </Badge>
                              </div>
                            </div>

                            <div className="flex flex-wrap items-center gap-2 md:justify-end">
                              {invoice.invoicePdfUrl ? (
                                <a
                                  href={invoice.invoicePdfUrl}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  aria-label={`Download invoice ${invoice.number ?? invoice.id} as PDF`}
                                >
                                  <Button
                                    size="sm"
                                    variant="outline"
                                    className="border-zinc-700 text-zinc-200 hover:text-white"
                                  >
                                    Download PDF
                                  </Button>
                                </a>
                              ) : null}
                              {invoice.hostedInvoiceUrl ? (
                                <a
                                  href={invoice.hostedInvoiceUrl}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  aria-label={`View invoice ${invoice.number ?? invoice.id} online`}
                                >
                                  <Button
                                    size="sm"
                                    variant="ghost"
                                    className="text-zinc-400 hover:text-white"
                                  >
                                    View online
                                  </Button>
                                </a>
                              ) : null}
                            </div>
                          </div>
                        </div>
                      </li>
                    ))}
                  </ul>

                  {data?.hasMore && (
                    <p className="mt-2 text-xs text-zinc-500">
                      Older invoices are available via the Stripe customer portal.
                    </p>
                  )}
                </>
              )}
            </CardContent>
          </Card>
        </div>
      </section>

      <Footer />
    </div>
  );
}
