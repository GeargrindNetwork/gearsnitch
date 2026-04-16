import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { getSubscription, createSubscription, cancelSubscription } from '@/lib/api';

const TIERS = [
  { key: 'hustle', name: 'HUSTLE', price: '$4.99/mo', features: ['Real-time BLE monitoring', 'Disconnect alerts', '1 gym', '3 devices'] },
  { key: 'hwmf', name: 'HWMF', price: '$60/yr', badge: 'Recommended', features: ['Everything in HUSTLE', 'Unlimited gyms', '10 devices', 'Panic alarm', 'Health sync'] },
  { key: 'babyMomma', name: 'BABY MOMMA', price: '$99 once', badge: 'Best Value', features: ['Everything in HWMF', 'Unlimited devices', 'Mesh chat', 'Lifetime updates'] },
] as const;

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

  const { data: sub, isLoading } = useQuery({
    queryKey: ['subscription'],
    queryFn: getSubscription,
    staleTime: 30_000,
  });

  const subscribeMutation = useMutation({
    mutationFn: (tier: string) => createSubscription(tier),
    onSuccess: (data) => {
      if (data.checkoutUrl) window.location.href = data.checkoutUrl;
      queryClient.invalidateQueries({ queryKey: ['subscription'] });
    },
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

            {isActive && currentTier !== 'lifetime' && (
              <Button variant="ghost" size="sm" className="mt-2 text-xs text-red-400" onClick={() => setShowCancel(true)}>
                Cancel Subscription
              </Button>
            )}
          </CardContent>
        </Card>

        {/* Available Plans */}
        <Card className="border-white/5 bg-zinc-900/70">
          <CardHeader className="pb-2"><CardTitle className="text-sm text-zinc-400">{isActive ? 'Upgrade Plan' : 'Choose a Plan'}</CardTitle></CardHeader>
          <CardContent className="space-y-3 pb-4">
            {TIERS.map(tier => {
              const isCurrent = tier.name === sub?.plan;
              return (
                <div key={tier.key} className={`rounded-lg border p-4 ${isCurrent ? 'border-emerald-500/30 bg-emerald-500/5' : 'border-white/5 bg-zinc-950'}`}>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-bold text-zinc-200">{tier.name}</span>
                      {tier.badge && <Badge variant="secondary" className="border-emerald-500/20 bg-emerald-500/10 text-[10px] text-emerald-400">{tier.badge}</Badge>}
                      {isCurrent && <Badge variant="secondary" className="border-emerald-500/20 bg-emerald-500/10 text-[10px] text-emerald-400">Current</Badge>}
                    </div>
                    <span className="text-sm font-semibold text-zinc-300">{tier.price}</span>
                  </div>
                  <ul className="mt-2 space-y-1">
                    {tier.features.map(f => (
                      <li key={f} className="flex items-center gap-1.5 text-xs text-zinc-400">
                        <span className="text-emerald-400">&#10003;</span> {f}
                      </li>
                    ))}
                  </ul>
                  {!isCurrent && (
                    <Button
                      size="sm"
                      className="mt-3 w-full bg-emerald-600 text-xs text-white hover:bg-emerald-700"
                      onClick={() => subscribeMutation.mutate(tier.key)}
                      disabled={subscribeMutation.isPending}
                    >
                      {subscribeMutation.isPending ? 'Processing...' : isActive ? 'Upgrade' : 'Subscribe'}
                    </Button>
                  )}
                </div>
              );
            })}
            {subscribeMutation.isError && <p className="text-xs text-red-400">{(subscribeMutation.error as Error).message}</p>}
          </CardContent>
        </Card>
      </div>

      {/* Cancel Confirmation */}
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
