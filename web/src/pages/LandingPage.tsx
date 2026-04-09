import { Link } from 'react-router-dom';
import { Button } from '../components/ui/button';
import { Card, CardContent } from '../components/ui/card';
import { Badge } from '../components/ui/badge';
import Header from '../components/layout/Header';
import Footer from '../components/layout/Footer';

const features = [
  {
    icon: '📡',
    title: 'Bluetooth Gear Monitoring',
    description:
      'Track your gym gear in real-time via Bluetooth. Get instant alerts when a device disconnects — never leave your gear behind.',
  },
  {
    icon: '📍',
    title: 'Gym Detection & Auto-Activate',
    description:
      'GearSnitch detects when you arrive at your gym and automatically activates gear monitoring. Leave and it deactivates.',
  },
  {
    icon: '🔔',
    title: 'Panic Alerts & Emergency Contacts',
    description:
      'Trigger panic alarms with sound, haptics, and push notifications. Emergency contacts are notified automatically.',
  },
  {
    icon: '💪',
    title: 'Workout & Health Tracking',
    description:
      'Log workouts, track calories and macros, sync with Apple Health, and monitor your fitness progress over time.',
  },
  {
    icon: '🎁',
    title: 'Referral Rewards',
    description:
      'Share your referral code and earn 90 days of free subscription credit for every friend who signs up and subscribes.',
  },
  {
    icon: '🧬',
    title: 'Peptide Store',
    description:
      'Browse and purchase premium peptide products with full compliance, age verification, and jurisdiction controls.',
  },
];

const steps = [
  {
    step: '01',
    title: 'Sign Up',
    description: 'Create your account with Apple or Google Sign-In. Quick, secure, passwordless.',
  },
  {
    step: '02',
    title: 'Pair Your Gear',
    description: 'Connect your Bluetooth devices — earbuds, trackers, gym bags, belts, and more.',
  },
  {
    step: '03',
    title: 'Set Your Gym',
    description: 'Save your gym location. GearSnitch auto-activates monitoring when you arrive.',
  },
  {
    step: '04',
    title: 'Stay Protected',
    description: 'Get instant alerts if anything disconnects. Focus on your workout, not your gear.',
  },
];

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      {/* Hero */}
      <section className="relative overflow-hidden px-6 py-24 sm:py-32 lg:px-8">
        <div className="absolute inset-0 bg-gradient-to-br from-zinc-950 via-zinc-900 to-zinc-950" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-emerald-900/20 via-transparent to-transparent" />

        <div className="relative mx-auto max-w-4xl text-center">
          <Badge variant="outline" className="mb-6 border-emerald-500/50 text-emerald-400">
            Now Available on iOS
          </Badge>

          <h1 className="text-5xl font-bold tracking-tight sm:text-7xl">
            Never Lose Your{' '}
            <span className="bg-gradient-to-r from-emerald-400 to-cyan-400 bg-clip-text text-transparent">
              Gym Gear
            </span>{' '}
            Again
          </h1>

          <p className="mt-6 text-lg leading-8 text-zinc-400 sm:text-xl">
            GearSnitch monitors your Bluetooth devices at the gym, alerts you instantly when something
            disconnects, and keeps your gear safe — automatically.
          </p>

          <div className="mt-10 flex items-center justify-center gap-x-4">
            <Button size="lg" className="bg-emerald-600 hover:bg-emerald-500 text-white px-8 py-6 text-lg">
              Download for iOS
            </Button>
            <Button
              variant="outline"
              size="lg"
              className="border-zinc-700 text-zinc-300 hover:bg-zinc-800 px-8 py-6 text-lg"
              asChild
            >
              <Link to="/store">Visit Store</Link>
            </Button>
          </div>

          <div className="mt-8 flex items-center justify-center gap-6 text-sm text-zinc-500">
            <span>Free to download</span>
            <span className="h-1 w-1 rounded-full bg-zinc-700" />
            <span>Apple Sign-In</span>
            <span className="h-1 w-1 rounded-full bg-zinc-700" />
            <span>No passwords</span>
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="px-6 py-24 lg:px-8">
        <div className="mx-auto max-w-6xl">
          <div className="text-center">
            <h2 className="text-3xl font-bold tracking-tight">Everything You Need at the Gym</h2>
            <p className="mt-4 text-zinc-400">
              Gear monitoring, workout tracking, health insights, and a curated store — all in one app.
            </p>
          </div>

          <div className="mt-16 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {features.map((feature) => (
              <Card
                key={feature.title}
                className="border-zinc-800 bg-zinc-900/50 hover:border-zinc-700 transition-colors"
              >
                <CardContent className="p-6">
                  <div className="text-3xl mb-4">{feature.icon}</div>
                  <h3 className="text-lg font-semibold text-zinc-100">{feature.title}</h3>
                  <p className="mt-2 text-sm text-zinc-400 leading-relaxed">{feature.description}</p>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="px-6 py-24 lg:px-8 bg-zinc-900/50">
        <div className="mx-auto max-w-4xl">
          <div className="text-center">
            <h2 className="text-3xl font-bold tracking-tight">How It Works</h2>
            <p className="mt-4 text-zinc-400">Get set up in under 2 minutes.</p>
          </div>

          <div className="mt-16 space-y-8">
            {steps.map((item) => (
              <div key={item.step} className="flex gap-6 items-start">
                <div className="flex-shrink-0 w-12 h-12 rounded-full bg-emerald-600/20 border border-emerald-500/30 flex items-center justify-center text-emerald-400 font-mono font-bold text-sm">
                  {item.step}
                </div>
                <div>
                  <h3 className="text-lg font-semibold text-zinc-100">{item.title}</h3>
                  <p className="mt-1 text-zinc-400">{item.description}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="px-6 py-24 lg:px-8">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-bold tracking-tight">
            Ready to Protect Your Gear?
          </h2>
          <p className="mt-4 text-zinc-400">
            Download GearSnitch and never worry about leaving your gear behind again.
          </p>
          <div className="mt-8">
            <Button size="lg" className="bg-emerald-600 hover:bg-emerald-500 text-white px-10 py-6 text-lg">
              Download for iOS
            </Button>
          </div>
          <p className="mt-4 text-sm text-zinc-500">
            Requires iOS 16 or later. Bluetooth-enabled devices required.
          </p>
        </div>
      </section>

      <Footer />
    </div>
  );
}
