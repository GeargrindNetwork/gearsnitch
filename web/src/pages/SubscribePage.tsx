import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { createSubscriptionCheckout, type WebSubscriptionTier } from '@/lib/api';
import { useAuth } from '@/lib/auth';

interface TierCard {
  key: WebSubscriptionTier;
  plan: string;
  price: string;
  cadence: string;
  badge?: string;
  highlight: boolean;
  blurb: string;
  perks: string[];
  cta: string;
  accent: string; // tailwind text color
}

const TIERS: TierCard[] = [
  {
    key: 'hustle',
    plan: 'HUSTLE',
    price: '$4.99',
    cadence: '/month',
    blurb: 'Perfect for getting started. All Pro features, billed monthly.',
    perks: [
      'Unlimited BLE gear monitoring',
      'Full panic alert system',
      'Health & workout tracking',
      'Cancel anytime',
    ],
    cta: 'Start HUSTLE',
    highlight: false,
    accent: 'text-cyan-400',
  },
  {
    key: 'hwmf',
    plan: 'HWMF',
    price: '$60',
    cadence: '/year',
    badge: 'Best Value',
    blurb: 'Save with annual billing. Two months free vs monthly.',
    perks: [
      'Everything in HUSTLE',
      'Priority support',
      'Annual billing',
      '7-day free trial',
    ],
    cta: 'Go Annual',
    highlight: true,
    accent: 'text-emerald-400',
  },
  {
    key: 'babyMomma',
    plan: 'BABY MOMMA',
    price: '$99',
    cadence: 'one-time',
    blurb: 'Pay once. Lifetime access to every Pro feature, forever.',
    perks: [
      'Everything in HWMF',
      'Lifetime updates',
      'No recurring billing',
      'All future Pro features',
    ],
    cta: 'Get Lifetime',
    highlight: false,
    accent: 'text-amber-400',
  },
];

export default function SubscribePage() {
  const navigate = useNavigate();
  const { isAuthenticated, status } = useAuth();
  const [pendingTier, setPendingTier] = useState<WebSubscriptionTier | null>(null);

  async function handleSubscribe(tier: WebSubscriptionTier) {
    if (status === 'bootstrapping') return;
    if (!isAuthenticated) {
      navigate(`/sign-in?redirect=${encodeURIComponent('/subscribe')}`);
      return;
    }

    setPendingTier(tier);
    try {
      const session = await createSubscriptionCheckout({
        tier,
        successUrl: `${window.location.origin}/account/subscription/success`,
        cancelUrl: `${window.location.origin}/subscribe`,
      });
      // Redirect the browser to Stripe-hosted Checkout. We do NOT use SPA
      // navigation — Stripe needs a full page hand-off.
      window.location.assign(session.checkoutUrl);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Could not start checkout';
      toast.error(message);
      setPendingTier(null);
    }
  }

  return (
    <div className="dark min-h-screen bg-black text-white">
      <Header />

      <main className="relative overflow-hidden pt-24 pb-16 sm:pt-32">
        {/* Background gradients to match landing/dark theme */}
        <div className="pointer-events-none absolute inset-0">
          <div className="absolute left-1/2 top-0 h-[600px] w-[800px] -translate-x-1/2 rounded-full bg-cyan-500/8 blur-3xl" />
          <div className="absolute right-0 top-1/4 h-[400px] w-[400px] rounded-full bg-emerald-500/5 blur-3xl" />
        </div>

        <section className="relative mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-3xl text-center">
            <Badge
              variant="secondary"
              className="mb-6 border border-cyan-500/20 bg-cyan-500/10 px-4 py-1.5 text-cyan-400"
            >
              GearSnitch Pro
            </Badge>
            <h1 className="text-4xl font-extrabold tracking-tight sm:text-5xl">
              Pick your{' '}
              <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-transparent">
                Pro plan.
              </span>
            </h1>
            <p className="mx-auto mt-6 max-w-xl text-lg text-zinc-400">
              Subscribe on the web for full access to GearSnitch Pro. Cancel anytime,
              switch tiers anytime, manage everything from your account.
            </p>
            <p className="mt-3 text-xs text-zinc-600">
              On iPhone? Subscribe directly in the app for managed Apple billing.
            </p>
          </div>

          <div
            data-testid="subscribe-tier-grid"
            className="mt-14 grid gap-6 lg:grid-cols-3"
          >
            {TIERS.map((tier) => (
              <Card
                key={tier.key}
                data-testid={`subscribe-tier-${tier.key}`}
                className={
                  tier.highlight
                    ? 'border-emerald-400/40 bg-zinc-900/80 ring-2 ring-emerald-400/20'
                    : 'border-white/5 bg-zinc-900/70'
                }
              >
                <CardHeader className="pb-2">
                  <div className="flex items-center justify-between">
                    <CardTitle className={`font-heading text-2xl ${tier.accent}`}>
                      {tier.plan}
                    </CardTitle>
                    {tier.badge && (
                      <Badge className="border border-emerald-400/40 bg-emerald-400/10 text-[10px] text-emerald-300">
                        {tier.badge}
                      </Badge>
                    )}
                  </div>
                </CardHeader>
                <CardContent className="space-y-5 pb-5">
                  <div className="flex items-baseline gap-1">
                    <span className="text-4xl font-bold text-white">{tier.price}</span>
                    <span className="text-sm text-zinc-500">{tier.cadence}</span>
                  </div>
                  <p className="text-sm text-zinc-400">{tier.blurb}</p>
                  <ul className="space-y-2 text-sm text-zinc-300">
                    {tier.perks.map((perk) => (
                      <li key={perk} className="flex items-start gap-2">
                        <svg
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                          className="mt-0.5 h-4 w-4 shrink-0 text-emerald-400"
                          aria-hidden="true"
                        >
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            d="M5 13l4 4L19 7"
                          />
                        </svg>
                        <span>{perk}</span>
                      </li>
                    ))}
                  </ul>
                  <Button
                    data-testid={`subscribe-cta-${tier.key}`}
                    type="button"
                    size="lg"
                    className={
                      tier.highlight
                        ? 'w-full bg-emerald-400 text-black hover:bg-emerald-300'
                        : 'w-full bg-cyan-400 text-black hover:bg-cyan-300'
                    }
                    onClick={() => handleSubscribe(tier.key)}
                    disabled={pendingTier !== null}
                  >
                    {pendingTier === tier.key ? 'Redirecting…' : tier.cta}
                  </Button>
                </CardContent>
              </Card>
            ))}
          </div>

          <p className="mt-10 text-center text-xs text-zinc-500">
            Secure checkout powered by Stripe. Promotion codes accepted.{' '}
            <Link to="/terms" className="text-zinc-300 underline-offset-2 hover:underline">
              Terms
            </Link>{' '}
            ·{' '}
            <Link to="/privacy" className="text-zinc-300 underline-offset-2 hover:underline">
              Privacy
            </Link>
          </p>
        </section>
      </main>

      <Footer />
    </div>
  );
}
