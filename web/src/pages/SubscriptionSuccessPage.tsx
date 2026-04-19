import { useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { getSubscription, type SubscriptionStatus } from '@/lib/api';

const POLL_INTERVAL_MS = 2000;
const POLL_TIMEOUT_MS = 20_000;

type FetchState = 'pending' | 'active' | 'timeout' | 'error';

function tierAccent(tier: string | null | undefined): string {
  switch (tier) {
    case 'monthly':
      return 'text-cyan-400';
    case 'annual':
      return 'text-emerald-400';
    case 'lifetime':
      return 'text-amber-400';
    default:
      return 'text-zinc-300';
  }
}

export default function SubscriptionSuccessPage() {
  const [searchParams] = useSearchParams();
  const sessionId = searchParams.get('session_id');

  const [state, setState] = useState<FetchState>('pending');
  const [sub, setSub] = useState<SubscriptionStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const cancelled = useRef(false);

  useEffect(() => {
    cancelled.current = false;
    const startedAt = Date.now();
    let timer: number | null = null;

    async function tick(): Promise<void> {
      if (cancelled.current) return;

      try {
        const current = await getSubscription();
        if (cancelled.current) return;

        setSub(current);

        if (current.status === 'active') {
          setState('active');
          return;
        }

        if (Date.now() - startedAt >= POLL_TIMEOUT_MS) {
          setState('timeout');
          return;
        }

        timer = window.setTimeout(() => {
          void tick();
        }, POLL_INTERVAL_MS);
      } catch (err) {
        if (cancelled.current) return;
        setError(err instanceof Error ? err.message : 'Failed to verify subscription');
        if (Date.now() - startedAt >= POLL_TIMEOUT_MS) {
          setState('error');
          return;
        }
        timer = window.setTimeout(() => {
          void tick();
        }, POLL_INTERVAL_MS);
      }
    }

    void tick();

    return () => {
      cancelled.current = true;
      if (timer !== null) {
        window.clearTimeout(timer);
      }
    };
  }, []);

  return (
    <div className="dark min-h-screen bg-black text-white">
      <Header />

      <main className="relative mx-auto max-w-2xl px-4 pt-32 pb-16 sm:px-6 lg:px-8">
        <Card className="border-white/5 bg-zinc-900/70">
          <CardContent className="space-y-5 p-8 text-center">
            {state === 'pending' && (
              <>
                <div className="mx-auto h-10 w-10 animate-spin rounded-full border-2 border-zinc-700 border-t-emerald-400" />
                <h1 className="text-2xl font-bold">Confirming your subscription…</h1>
                <p className="text-sm text-zinc-400">
                  Stripe is finalizing your payment. This usually takes just a few seconds.
                </p>
                {sessionId && (
                  <p className="text-[10px] text-zinc-600" data-testid="subscription-session-id">
                    Session: {sessionId.slice(0, 14)}…
                  </p>
                )}
              </>
            )}

            {state === 'active' && (
              <>
                <div
                  className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-emerald-400/15 text-emerald-400"
                  aria-hidden="true"
                >
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    className="h-6 w-6"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                </div>
                <h1 className="text-3xl font-extrabold">
                  Welcome to{' '}
                  <span className={tierAccent(sub?.tier)}>{sub?.plan ?? 'GearSnitch Pro'}</span>!
                </h1>
                <p className="text-sm text-zinc-400">
                  Your subscription is active. Open the app or your account dashboard to start
                  using every Pro feature.
                </p>
                <div className="flex flex-col gap-3 sm:flex-row sm:justify-center">
                  <Link to="/account">
                    <Button size="lg" className="w-full bg-emerald-400 text-black hover:bg-emerald-300 sm:w-auto">
                      Go to Dashboard
                    </Button>
                  </Link>
                  <Link to="/metrics">
                    <Button size="lg" variant="outline" className="w-full sm:w-auto">
                      View Metrics
                    </Button>
                  </Link>
                </div>
              </>
            )}

            {state === 'timeout' && (
              <>
                <h1 className="text-2xl font-bold">Almost there…</h1>
                <p className="text-sm text-zinc-400">
                  Your payment is being processed but the confirmation hasn't reached our
                  servers yet. This is rare — please refresh in a moment, or check your account
                  page.
                </p>
                <div className="flex flex-col gap-3 sm:flex-row sm:justify-center">
                  <Link to="/account">
                    <Button size="lg" variant="outline" className="w-full sm:w-auto">
                      Go to Account
                    </Button>
                  </Link>
                  <Button
                    type="button"
                    size="lg"
                    onClick={() => window.location.reload()}
                  >
                    Refresh
                  </Button>
                </div>
              </>
            )}

            {state === 'error' && (
              <>
                <h1 className="text-2xl font-bold text-red-400">Couldn't verify subscription</h1>
                <p className="text-sm text-zinc-400">
                  {error ?? 'Something went wrong while checking your subscription state.'}
                </p>
                <p className="text-xs text-zinc-500">
                  If you completed payment, your subscription will activate momentarily — please
                  refresh or contact support.
                </p>
                <div className="flex flex-col gap-3 sm:flex-row sm:justify-center">
                  <Link to="/support">
                    <Button size="lg" variant="outline" className="w-full sm:w-auto">
                      Contact Support
                    </Button>
                  </Link>
                  <Link to="/account">
                    <Button size="lg" className="w-full sm:w-auto">
                      Go to Account
                    </Button>
                  </Link>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </main>

      <Footer />
    </div>
  );
}
