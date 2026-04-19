/**
 * Landing variant v2 — benefits-forward (item #36).
 *
 * Tests a more outcome-focused framing against the v1 control:
 *   - Hero headline leads with the visitor's win ("Never lose gym gear again.")
 *     instead of the product mechanic ("Never lose your gym gear").
 *   - Hero CTAs are re-copy'd as outcomes ("Protect My Gear" /
 *     "See How It Works") rather than actions ("Download for iOS" /
 *     "Visit Store").
 *   - The "How It Works" 4-step grid is replaced with an outcome-oriented
 *     two-column "Real benefits" block that pairs each benefit with the
 *     problem it solves — a meaningful layout change, not just a copy swap.
 *
 * Shared chrome (Header / Footer / AppScreenshotsSwiper) and the feature card
 * grid are kept intact so we isolate the copy/layout change at the top and
 * middle of the page.
 */
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import AppScreenshotsSwiper from '@/components/landing/AppScreenshotsSwiper';

const benefits = [
  {
    problem: 'You leave the gym and realize your AirPods are gone.',
    promise: 'Instant alerts the second anything disconnects.',
    detail:
      'GearSnitch watches every paired device while you train. If a bag, belt, tracker, or pair of buds leaves Bluetooth range, you know before you walk out the door.',
  },
  {
    problem: 'Your gear grows — your phone stays cluttered.',
    promise: 'One dashboard for every Bluetooth device you own.',
    detail:
      'Pair earbuds, smart scales, heart-rate straps, gym bags, and more. Battery, last-seen time, and owner profile all live in a single clean timeline.',
  },
  {
    problem: 'Tracking workouts manually kills consistency.',
    promise: 'Auto-start the moment you enter your gym.',
    detail:
      'Geo-fenced zones trigger session tracking automatically. No buttons, no lag — just walk in, train, and walk out with clean data.',
  },
  {
    problem: 'Consistency should pay you back.',
    promise: 'Member pricing on the supplements you already buy.',
    detail:
      'Every session unlocks rewards at the GearSnitch peptide + recovery store. Active paid plans also stack 28-day referral bonuses per friend.',
  },
];

const features = [
  {
    title: 'BLE Gear Monitoring',
    description: 'Automatic Bluetooth presence tracking for every paired device — no manual check-ins.',
  },
  {
    title: 'Gym Auto-Activation',
    description: 'Walk into a partnered gym and protection turns on by itself. Step out and it stands down.',
  },
  {
    title: 'Panic + Recovery Alerts',
    description: 'Push, sound, and haptic alarms the moment something disconnects unexpectedly.',
  },
  {
    title: 'Rewards That Compound',
    description: 'Earn 28 bonus days per qualified referral, plus member pricing at the peptide store.',
  },
  {
    title: 'Built for Privacy',
    description: 'End-to-end encryption, local-first processing, zero data sold. Your training stays yours.',
  },
  {
    title: 'iPhone + Apple Watch',
    description: 'Monitor from your wrist, get alerts on your phone, and keep everything synced to the web.',
  },
];

export default function LandingV2() {
  return (
    // Landing page pins to dark theme regardless of user preference
    // (matches v1 control to isolate copy/layout as the only variable).
    <div className="dark min-h-screen bg-black text-white" data-landing-variant="v2">
      <Header />

      {/* Hero — benefits-forward headline + outcome CTAs */}
      <section className="relative overflow-hidden pt-16">
        <div className="pointer-events-none absolute inset-0">
          <div className="absolute left-1/2 top-0 h-[600px] w-[800px] -translate-x-1/2 rounded-full bg-cyan-500/8 blur-3xl" />
          <div className="absolute right-0 top-1/4 h-[400px] w-[400px] rounded-full bg-emerald-500/5 blur-3xl" />
        </div>

        <div className="relative mx-auto max-w-7xl px-4 pb-20 pt-24 sm:px-6 sm:pt-32 lg:px-8 lg:pt-40">
          <div className="mx-auto max-w-3xl text-center">
            <Badge variant="secondary" className="mb-6 border border-emerald-500/20 bg-emerald-500/10 px-4 py-1.5 text-emerald-400">
              Trusted by 10,000+ athletes
            </Badge>

            <h1 className="text-4xl font-extrabold tracking-tight sm:text-5xl lg:text-7xl">
              Never lose gym gear
              <br />
              <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-transparent">
                again. Ever.
              </span>
            </h1>

            <p className="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-zinc-300 sm:text-xl">
              GearSnitch is a Bluetooth bodyguard for your training kit. Pair it once,
              train anywhere, and get an instant alert the moment something leaves your side.
            </p>

            <div className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row">
              <a href="#benefits">
                <Button size="lg" className="h-14 min-w-[220px] bg-gradient-to-r from-cyan-500 to-emerald-500 text-base font-bold text-black transition-all hover:from-cyan-400 hover:to-emerald-400 hover:shadow-lg hover:shadow-cyan-500/25">
                  Protect My Gear
                </Button>
              </a>
              <Link to="/store">
                <Button size="lg" variant="outline" className="h-14 min-w-[220px] border-zinc-700 text-base font-bold text-white transition-all hover:border-zinc-500 hover:bg-white/5">
                  See How It Works
                </Button>
              </Link>
            </div>

            <div className="mt-12 flex items-center justify-center gap-8 text-sm text-zinc-500">
              <div className="flex flex-col items-center">
                <span className="text-2xl font-bold text-white">Under 60s</span>
                <span>To Set Up</span>
              </div>
              <Separator orientation="vertical" className="h-10 bg-zinc-800" />
              <div className="flex flex-col items-center">
                <span className="text-2xl font-bold text-white">4.9</span>
                <span>App Store Rating</span>
              </div>
              <Separator orientation="vertical" className="h-10 bg-zinc-800" />
              <div className="flex flex-col items-center">
                <span className="text-2xl font-bold text-white">$29.99/yr</span>
                <span>All-in Price</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <AppScreenshotsSwiper />

      {/* Benefits — two-column problem/promise layout (replaces v1's 4-step "How It Works") */}
      <section id="benefits" className="relative border-t border-white/5 bg-zinc-950 py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <Badge variant="secondary" className="mb-4 border border-emerald-500/20 bg-emerald-500/10 text-emerald-400">
              Real benefits
            </Badge>
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Your training is serious.
              <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-transparent"> So is your gear.</span>
            </h2>
            <p className="mt-4 text-lg text-zinc-400">
              Here is exactly what changes the day you install GearSnitch.
            </p>
          </div>

          <div className="mt-16 space-y-6">
            {benefits.map((item, idx) => (
              <div
                key={item.promise}
                className="grid gap-6 rounded-2xl border border-white/5 bg-zinc-900/40 p-8 transition-all hover:border-emerald-500/20 hover:bg-zinc-900/70 md:grid-cols-2"
              >
                <div>
                  <div className="mb-3 inline-flex h-8 items-center rounded-full border border-white/10 bg-black/30 px-3 text-xs font-semibold uppercase tracking-wider text-zinc-400">
                    Before · {String(idx + 1).padStart(2, '0')}
                  </div>
                  <p className="text-lg text-zinc-400">{item.problem}</p>
                </div>
                <div>
                  <div className="mb-3 inline-flex h-8 items-center rounded-full border border-emerald-500/20 bg-emerald-500/10 px-3 text-xs font-semibold uppercase tracking-wider text-emerald-400">
                    After GearSnitch
                  </div>
                  <h3 className="text-lg font-semibold text-white">{item.promise}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-zinc-400">{item.detail}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features strip — terser cards that back up the benefit claims above */}
      <section id="features" className="border-t border-white/5 py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <Badge variant="secondary" className="mb-4 border border-cyan-500/20 bg-cyan-500/10 text-cyan-400">
              What you get
            </Badge>
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Built to disappear into your workout
            </h2>
            <p className="mt-4 text-lg text-zinc-400">
              Everything runs in the background so you can focus on training.
            </p>
          </div>

          <div className="mt-16 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {features.map((feature) => (
              <Card
                key={feature.title}
                className="group border-white/5 bg-zinc-900/50 transition-all hover:border-cyan-500/20 hover:bg-zinc-900"
              >
                <CardContent className="p-6">
                  <h3 className="mb-2 text-lg font-semibold text-white">{feature.title}</h3>
                  <p className="text-sm leading-relaxed text-zinc-400">{feature.description}</p>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* Download CTA — identical anchor + pricing as v1 so conversion metrics compare cleanly */}
      <section id="download" className="border-t border-white/5 py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="relative overflow-hidden rounded-3xl border border-white/5 bg-gradient-to-br from-zinc-900 via-zinc-900 to-zinc-800 p-12 text-center sm:p-16">
            <div className="pointer-events-none absolute inset-0">
              <div className="absolute left-1/2 top-0 h-[300px] w-[500px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-emerald-500/10 blur-3xl" />
            </div>

            <div className="relative">
              <h2 className="text-3xl font-bold tracking-tight sm:text-4xl lg:text-5xl">
                Stop losing gear.
                <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-transparent"> Start today.</span>
              </h2>
              <p className="mx-auto mt-4 max-w-xl text-lg text-zinc-400">
                Free to download. Full protection at $29.99/year. One price, every feature, no upsells.
              </p>

              <div className="mt-8 flex flex-col items-center justify-center gap-4 sm:flex-row">
                <Button size="lg" className="h-14 min-w-[220px] bg-gradient-to-r from-cyan-500 to-emerald-500 text-base font-bold text-black transition-all hover:from-cyan-400 hover:to-emerald-400 hover:shadow-lg hover:shadow-cyan-500/25">
                  Get GearSnitch Free
                </Button>
                <Button size="lg" variant="outline" className="h-14 min-w-[220px] border-zinc-700 text-base font-bold text-white hover:border-zinc-500 hover:bg-white/5">
                  Google Play (Soon)
                </Button>
              </div>

              <p className="mt-6 text-sm text-zinc-600">
                Requires iOS 16+. Cancel anytime. Your data never leaves your account.
              </p>
            </div>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
