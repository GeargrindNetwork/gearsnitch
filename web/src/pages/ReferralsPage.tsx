import { useQuery } from '@tanstack/react-query';
import { useCallback, useState } from 'react';
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
// Types (mirror the /referrals/me + /referrals/qr payload shapes in api/src/modules/referrals/routes.ts)
// ---------------------------------------------------------------------------

type ReferralHistoryStatus = 'pending' | 'completed' | 'expired';

interface ReferralHistoryEntry {
  _id: string;
  referredEmail: string | null;
  status: ReferralHistoryStatus;
  createdAt: string;
}

interface ReferralSummary {
  referralCode: string;
  referralURL: string;
  totalReferrals: number;
  activeReferrals: number;
  extensionDaysEarned: number;
  history: ReferralHistoryEntry[];
}

interface ReferralQrPayload {
  referralCode: string;
  referralURL: string;
  qrPayload: string;
}

// ---------------------------------------------------------------------------
// Data fetchers
// ---------------------------------------------------------------------------

async function fetchReferralSummary(): Promise<ReferralSummary> {
  const res = await api.get<ReferralSummary>('/referrals/me');
  if (!res.success || !res.data) {
    throw new Error(res.error?.message ?? 'Failed to load referral summary');
  }
  return res.data;
}

async function fetchReferralQr(): Promise<ReferralQrPayload> {
  const res = await api.get<ReferralQrPayload>('/referrals/qr');
  if (!res.success || !res.data) {
    throw new Error(res.error?.message ?? 'Failed to load referral QR');
  }
  return res.data;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function statusBadgeClass(status: ReferralHistoryStatus): string {
  switch (status) {
    case 'completed':
      return 'border-emerald-700 text-emerald-400';
    case 'expired':
      return 'border-rose-700 text-rose-400';
    default:
      return 'border-zinc-700 text-zinc-400';
  }
}

function statusLabel(status: ReferralHistoryStatus): string {
  switch (status) {
    case 'completed':
      return 'Rewarded';
    case 'expired':
      return 'Expired';
    default:
      return 'Pending';
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function ReferralsPage() {
  const { isAuthenticated } = useAuth();
  const [copied, setCopied] = useState<'code' | 'url' | null>(null);

  const summaryQuery = useQuery<ReferralSummary>({
    queryKey: ['referrals', 'me'],
    queryFn: fetchReferralSummary,
    enabled: isAuthenticated,
    retry: false,
  });

  const qrQuery = useQuery<ReferralQrPayload>({
    queryKey: ['referrals', 'qr'],
    queryFn: fetchReferralQr,
    enabled: isAuthenticated,
    retry: false,
  });

  const summary = summaryQuery.data;
  const qr = qrQuery.data;

  const handleCopy = useCallback(async (value: string, field: 'code' | 'url') => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(field);
      toast.success(field === 'code' ? 'Referral code copied' : 'Referral link copied');
      window.setTimeout(() => setCopied((current) => (current === field ? null : current)), 1600);
    } catch {
      toast.error('Could not copy to clipboard');
    }
  }, []);

  const handleShare = useCallback(async (shareURL: string, code: string) => {
    const shareData = {
      title: 'Join me on GearSnitch',
      text: `Use my referral code ${code} for bonus days on GearSnitch.`,
      url: shareURL,
    };

    if (typeof navigator.share === 'function') {
      try {
        await navigator.share(shareData);
        return;
      } catch {
        // user cancelled or share unavailable; fall through to copy
      }
    }

    await handleCopy(shareURL, 'url');
  }, [handleCopy]);

  const isLoading = summaryQuery.isLoading || qrQuery.isLoading;
  const error = summaryQuery.error ?? qrQuery.error;

  return (
    <div className="dark min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <main className="mx-auto max-w-4xl space-y-6 px-6 pb-16 pt-28 lg:px-8">
        <section className="space-y-2">
          <Badge
            variant="secondary"
            className="border border-cyan-500/20 bg-cyan-500/10 text-cyan-400"
          >
            Referrals
          </Badge>
          <h1 className="text-3xl font-bold tracking-tight">Share GearSnitch, earn bonus days</h1>
          <p className="max-w-2xl text-sm text-zinc-400">
            Every friend who redeems your code and subscribes adds 28 bonus days to your plan.
            Share your code or QR anywhere — the code works in the iOS app and on the web.
          </p>
        </section>

        {isLoading && (
          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardContent className="py-12 text-center text-zinc-500">
              Loading your referral dashboard...
            </CardContent>
          </Card>
        )}

        {!isLoading && error && (
          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardHeader>
              <CardTitle>Referrals Unavailable</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-zinc-400">
              <p>{error instanceof Error ? error.message : 'Failed to load your referral data.'}</p>
              <p className="text-sm text-zinc-500">
                Try refreshing the page. If the problem persists, sign out and sign back in.
              </p>
            </CardContent>
          </Card>
        )}

        {!isLoading && !error && summary && (
          <>
            {/* Stats */}
            <section className="grid gap-4 sm:grid-cols-3">
              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader className="pb-2">
                  <CardTitle className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                    Bonus Days
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-3xl font-bold text-emerald-400">
                    {summary.extensionDaysEarned}
                  </p>
                  <p className="text-xs text-zinc-500">earned from referrals</p>
                </CardContent>
              </Card>

              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader className="pb-2">
                  <CardTitle className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                    Active Referrals
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-3xl font-bold text-white">{summary.activeReferrals}</p>
                  <p className="text-xs text-zinc-500">qualified or rewarded</p>
                </CardContent>
              </Card>

              <Card className="border-zinc-800 bg-zinc-900/50">
                <CardHeader className="pb-2">
                  <CardTitle className="text-xs uppercase tracking-[0.16em] text-zinc-500">
                    Total Referred
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-3xl font-bold text-white">{summary.totalReferrals}</p>
                  <p className="text-xs text-zinc-500">all-time</p>
                </CardContent>
              </Card>
            </section>

            {/* Code + QR */}
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardHeader>
                <CardTitle>Your Referral Code</CardTitle>
              </CardHeader>
              <CardContent className="grid gap-6 md:grid-cols-[1fr_auto]">
                <div className="space-y-4">
                  <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4">
                    <p className="text-xs uppercase tracking-[0.16em] text-zinc-500">Code</p>
                    <div className="mt-2 flex items-center justify-between gap-3">
                      <code className="font-mono text-2xl text-emerald-400">
                        {summary.referralCode}
                      </code>
                      <Button
                        size="sm"
                        variant="outline"
                        className="border-zinc-700 text-zinc-200 hover:text-white"
                        onClick={() => handleCopy(summary.referralCode, 'code')}
                      >
                        {copied === 'code' ? 'Copied' : 'Copy'}
                      </Button>
                    </div>
                  </div>

                  <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4">
                    <p className="text-xs uppercase tracking-[0.16em] text-zinc-500">Share Link</p>
                    <div className="mt-2 flex items-center justify-between gap-3">
                      <code className="truncate font-mono text-sm text-zinc-300">
                        {summary.referralURL}
                      </code>
                      <div className="flex shrink-0 gap-2">
                        <Button
                          size="sm"
                          variant="outline"
                          className="border-zinc-700 text-zinc-200 hover:text-white"
                          onClick={() => handleCopy(summary.referralURL, 'url')}
                        >
                          {copied === 'url' ? 'Copied' : 'Copy'}
                        </Button>
                        <Button
                          size="sm"
                          className="bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400"
                          onClick={() => handleShare(summary.referralURL, summary.referralCode)}
                        >
                          Share
                        </Button>
                      </div>
                    </div>
                  </div>

                  <p className="text-xs text-zinc-500">
                    Referred users must start a qualifying paid plan for the bonus days to apply.
                    Rewards stack while your own subscription stays active.
                  </p>
                </div>

                {qr && (
                  <div className="flex min-w-[220px] flex-col items-center justify-center gap-3 rounded-lg border border-zinc-800 bg-zinc-950 p-4 text-center">
                    <div
                      aria-hidden="true"
                      className="flex h-32 w-32 items-center justify-center rounded-md border border-zinc-700 bg-zinc-900 text-4xl text-zinc-600"
                    >
                      QR
                    </div>
                    <p className="text-xs text-zinc-400">
                      Open the GearSnitch iOS app to show a scannable QR.
                    </p>
                    <Button
                      size="sm"
                      variant="outline"
                      className="border-zinc-700 text-zinc-200 hover:text-white"
                      onClick={() => handleCopy(qr.qrPayload, 'url')}
                    >
                      Copy QR link
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>

            {/* History */}
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardHeader>
                <CardTitle>Referral History</CardTitle>
              </CardHeader>
              <CardContent>
                {summary.history.length === 0 ? (
                  <p className="text-sm text-zinc-400">
                    No one has redeemed your code yet. Share your code with a friend to get
                    started — you both benefit.
                  </p>
                ) : (
                  <ul className="space-y-2">
                    {summary.history.map((entry, index) => (
                      <li key={entry._id}>
                        {index > 0 && <Separator className="my-2 bg-zinc-800" />}
                        <div className="flex items-center justify-between gap-3 rounded-lg px-1 py-2">
                          <div className="min-w-0">
                            <p className="truncate text-sm text-zinc-200">
                              {entry.referredEmail ?? 'Pending signup'}
                            </p>
                            <p className="text-xs text-zinc-500">
                              Invited {formatDate(entry.createdAt)}
                            </p>
                          </div>
                          <Badge
                            variant="outline"
                            className={statusBadgeClass(entry.status)}
                          >
                            {statusLabel(entry.status)}
                          </Badge>
                        </div>
                      </li>
                    ))}
                  </ul>
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
