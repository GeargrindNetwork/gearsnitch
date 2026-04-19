import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { getSubscription, cancelSubscription } from '@/lib/api';

const APP_STORE_SUBSCRIPTIONS_URL = 'https://apps.apple.com/account/subscriptions';

function tierColor(tier: string) {
  switch (tier) {
    case 'monthly': return 'text-cyan-400';
    case 'annual': return 'text-emerald-400';
    case 'lifetime': return 'text-amber-400';
    default: return 'text-zinc-400';
  }
}

function formatDate(iso: string | null) {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('en-US', { month: 'long', day: 'numeric', year: 'numeric' }).format(new Date(iso));
}

export default function SubscriptionPanel() {
  const queryClient = useQueryClient();
  const [showCancel, setShowCancel] = useState(false);
  const [showWebHelper, setShowWebHelper] = useState(false);

  const { data: sub, isLoading } = useQuery({
    queryKey: ['subscription'],
    queryFn: getSubscription,
    staleTime: 30_000,
  });

  const cancelMutation = useMutation({
    mutationFn: cancelSubscription,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['subscription'] });
      setShowCancel(false);
    },
  });

  if (isLoading) {
    return <Card className="border-white/5 bg-zinc-900/70"><CardContent className="p-6 text-sm text-zinc-400">Loading subscription...</CardContent></Card>;
  }

  const isActive = sub?.status === 'active';
  const currentTier = sub?.tier;
  const platform = sub?.platform ?? null;
  const isStripeSub = platform === 'stripe';
  const isIosSub = platform === 'ios' || platform === 'apple' || platform === 'appstore' || platform === 'app_store';

  return (
    <>
      <div className="space-y-4">
        {/* Current Plan */}
        <Card className="border-white/5 bg-zinc-900/70">
          <CardHeader className="pb-2"><CardTitle className="text-sm text-zinc-400">Current Plan</CardTitle></CardHeader>
          <CardContent className="space-y-2 pb-4">
            <div className="flex items-center gap-3">
              <span className={`text-2xl font-bold ${tierColor(currentTier || '')}`}>{sub?.plan || 'Free'}</span>
              <Badge variant="outline" className={`text-[10px] ${isActive ? 'border-emerald-400/30 bg-emerald-400/10 text-emerald-300' : 'border-zinc-400/30 bg-zinc-400/10 text-zinc-300'}`}>
                {sub?.status || 'none'}
              </Badge>
            </div>
            {sub?.purchaseDate && <p className="text-xs text-zinc-500">Purchased: {formatDate(sub.purchaseDate)}</p>}
            {sub?.expiresAt && currentTier !== 'lifetime' && <p className="text-xs text-zinc-500">Renews: {formatDate(sub.expiresAt)}</p>}
            {currentTier === 'lifetime' && <p className="text-xs text-emerald-400">Lifetime — never expires</p>}
            {sub?.platform && <p className="text-xs text-zinc-600">Platform: {sub.platform}</p>}

            {isActive && currentTier !== 'lifetime' && isStripeSub && (
              <Button variant="ghost" size="sm" className="mt-2 text-xs text-red-400" onClick={() => setShowCancel(true)}>
                Cancel Subscription
              </Button>
            )}

            {isActive && isIosSub && (
              <a
                href={APP_STORE_SUBSCRIPTIONS_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-2 inline-block text-xs text-cyan-400 underline-offset-2 hover:underline"
              >
                Manage in App Store → Subscriptions
              </a>
            )}
          </CardContent>
        </Card>

        {/* iOS-first messaging for users without an active subscription */}
        {!isActive && (
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm text-zinc-400">Get GearSnitch Pro</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 pb-4">
              <div className="rounded-lg border border-white/5 bg-zinc-950 p-4">
                <p className="text-sm font-semibold text-zinc-100">
                  GearSnitch subscriptions are purchased in the iOS app.
                </p>
                <p className="mt-2 text-xs text-zinc-400">
                  Open the app → Settings → Upgrade to Pro.
                </p>
              </div>

              <button
                type="button"
                className="text-left text-xs text-zinc-500 underline-offset-2 hover:text-zinc-300 hover:underline"
                onClick={() => setShowWebHelper((prev) => !prev)}
                aria-expanded={showWebHelper}
              >
                Why can&apos;t I subscribe on the web?
              </button>

              {showWebHelper && (
                <p className="rounded-md border border-white/5 bg-zinc-950/60 p-3 text-xs leading-relaxed text-zinc-400">
                  GearSnitch uses Apple&apos;s in-app purchase system for iOS subscriptions so your
                  billing, renewals, and family sharing stay managed inside your Apple ID. Web
                  checkout (Stripe) is on the roadmap — for now, please complete your purchase in
                  the iPhone app.
                </p>
              )}
            </CardContent>
          </Card>
        )}
      </div>

      {/* Cancel Confirmation — Stripe subs only */}
      <Dialog open={showCancel} onOpenChange={setShowCancel}>
        <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100">
          <DialogHeader><DialogTitle>Cancel Subscription</DialogTitle></DialogHeader>
          <p className="text-sm text-zinc-400">Are you sure you want to cancel your subscription? You'll lose access to premium features at the end of your billing period.</p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowCancel(false)}>Keep Plan</Button>
            <Button variant="destructive" onClick={() => cancelMutation.mutate()} disabled={cancelMutation.isPending}>
              {cancelMutation.isPending ? 'Cancelling...' : 'Cancel Subscription'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
