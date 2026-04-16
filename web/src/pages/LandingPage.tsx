import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import AppScreenshotsSwiper from '@/components/landing/AppScreenshotsSwiper';

const features = [
  {
    icon: (
      <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M9.348 14.652a3.75 3.75 0 010-5.304m5.304 0a3.75 3.75 0 010 5.304m-7.425 2.121a6.75 6.75 0 010-9.546m9.546 0a6.75 6.75 0 010 9.546M5.106 18.894c-3.808-3.807-3.808-9.98 0-13.788m13.788 0c3.808 3.807 3.808 9.98 0 13.788M12 12h.008v.008H12V12zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" />
      </svg>
    ),
    title: 'BLE Gear Monitoring',
    description: 'Automatically detect and track Bluetooth-enabled fitness equipment around you. Know exactly what gear is nearby and get alerts if anything disconnects.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M15 10.5a3 3 0 11-6 0 3 3 0 016 0z" />
        <path d="M19.5 10.5c0 7.142-7.5 11.25-7.5 11.25S4.5 17.642 4.5 10.5a7.5 7.5 0 1115 0z" />
      </svg>
    ),
    title: 'Gym Detection',
    description: 'Step into any partnered gym and your app activates automatically. Geo-fenced zones trigger session tracking the moment you walk in.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M14.857 17.082a23.848 23.848 0 005.454-1.31A8.967 8.967 0 0118 9.75v-.7V9A6 6 0 006 9v.75a8.967 8.967 0 01-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 01-5.714 0m5.714 0a3 3 0 11-5.714 0" />
      </svg>
    ),
    title: 'Panic Alerts',
    description: 'Trigger panic alarms with sound, haptics, and push notifications when gear disconnects unexpectedly. Emergency contacts notified automatically.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M18 18.72a9.094 9.094 0 003.741-.479 3 3 0 00-4.682-2.72m.94 3.198l.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0112 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 016 18.719m12 0a5.971 5.971 0 00-.941-3.197m0 0A5.995 5.995 0 0012 12.75a5.995 5.995 0 00-5.058 2.772m0 0a3 3 0 00-4.681 2.72 8.986 8.986 0 003.74.477m.94-3.197a5.971 5.971 0 00-.94 3.197M15 6.75a3 3 0 11-6 0 3 3 0 016 0zm6 3a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0zm-13.5 0a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0z" />
      </svg>
    ),
    title: 'Referral Rewards',
    description: 'Invite friends and earn 28 bonus days for every qualifying referral while you stay on an active paid plan.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M15.75 10.5V6a3.75 3.75 0 10-7.5 0v4.5m11.356-1.993l1.263 12c.07.665-.45 1.243-1.119 1.243H4.25a1.125 1.125 0 01-1.12-1.243l1.264-12A1.125 1.125 0 015.513 7.5h12.974c.576 0 1.059.435 1.119 1.007zM8.625 10.5a.375.375 0 11-.75 0 .375.375 0 01.75 0zm7.5 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" />
      </svg>
    ),
    title: 'Peptide Store',
    description: 'Research-grade peptides, performance supplements, and recovery essentials. Lab-tested, compliance-verified, shipped discreetly.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M9 12.75L11.25 15 15 9.75m-3-7.036A11.959 11.959 0 013.598 6 11.99 11.99 0 003 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285z" />
      </svg>
    ),
    title: 'Privacy First',
    description: 'Your health data stays yours. End-to-end encryption, local-first processing, and zero data selling. Period.',
  },
];

const steps = [
  {
    step: '01',
    title: 'Download the App',
    description: 'Available on iOS. Set up your profile in under 60 seconds with Apple or Google Sign-In.',
  },
  {
    step: '02',
    title: 'Pair Your Gear',
    description: 'Connect your Bluetooth devices -- earbuds, trackers, gym bags, belts, and more.',
  },
  {
    step: '03',
    title: 'Walk Into Any Gym',
    description: 'GearSnitch auto-detects your location and activates BLE monitoring for your paired equipment.',
  },
  {
    step: '04',
    title: 'Stay Protected & Level Up',
    description: 'Get instant alerts if gear disconnects. Earn rewards, unlock insights, and shop at member prices.',
  },
];

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-black text-white">
      <Header />

      {/* Hero */}
      <section className="relative overflow-hidden pt-16">
        {/* Gradient background effects */}
        <div className="pointer-events-none absolute inset-0">
          <div className="absolute left-1/2 top-0 h-[600px] w-[800px] -translate-x-1/2 rounded-full bg-cyan-500/8 blur-3xl" />
          <div className="absolute right-0 top-1/4 h-[400px] w-[400px] rounded-full bg-emerald-500/5 blur-3xl" />
        </div>

        <div className="relative mx-auto max-w-7xl px-4 pb-20 pt-24 sm:px-6 sm:pt-32 lg:px-8 lg:pt-40">
          <div className="mx-auto max-w-3xl text-center">
            <Badge variant="secondary" className="mb-6 border border-cyan-500/20 bg-cyan-500/10 px-4 py-1.5 text-cyan-400">
              Now Available on iOS
            </Badge>

            <h1 className="text-4xl font-extrabold tracking-tight sm:text-5xl lg:text-7xl">
              Never Lose Your
              <br />
              <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-transparent">
                Gym Gear Again.
              </span>
            </h1>

            <p className="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-zinc-400 sm:text-xl">
              GearSnitch monitors your Bluetooth devices at the gym, alerts you instantly
              when something disconnects, and rewards your consistency with premium supplements.
            </p>

            <div className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row">
              <a href="#download">
                <Button size="lg" className="h-14 min-w-[200px] bg-gradient-to-r from-cyan-500 to-emerald-500 text-base font-bold text-black transition-all hover:from-cyan-400 hover:to-emerald-400 hover:shadow-lg hover:shadow-cyan-500/25">
                  <svg viewBox="0 0 24 24" className="mr-2 h-5 w-5" fill="currentColor">
                    <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
                  </svg>
                  Download for iOS
                </Button>
              </a>
              <Link to="/store">
                <Button size="lg" variant="outline" className="h-14 min-w-[200px] border-zinc-700 text-base font-bold text-white transition-all hover:border-zinc-500 hover:bg-white/5">
                  Visit Store
                </Button>
              </Link>
            </div>

            {/* Social proof */}
            <div className="mt-12 flex items-center justify-center gap-8 text-sm text-zinc-500">
              <div className="flex flex-col items-center">
                <span className="text-2xl font-bold text-white">10K+</span>
                <span>Beta Users</span>
              </div>
              <Separator orientation="vertical" className="h-10 bg-zinc-800" />
              <div className="flex flex-col items-center">
                <span className="text-2xl font-bold text-white">500+</span>
                <span>Gyms</span>
              </div>
              <Separator orientation="vertical" className="h-10 bg-zinc-800" />
              <div className="flex flex-col items-center">
                <span className="text-2xl font-bold text-white">4.9</span>
                <span>App Rating</span>
              </div>
            </div>
          </div>

          {/* Phone mockup */}
          <div className="relative mx-auto mt-16 max-w-sm">
            <div className="aspect-[9/19] overflow-hidden rounded-[2.5rem] border-2 border-zinc-800 bg-gradient-to-b from-zinc-900 to-zinc-950 shadow-2xl shadow-cyan-500/10">
              <div className="flex h-full flex-col items-center justify-center p-8">
                <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-cyan-400 to-emerald-400">
                  <svg viewBox="0 0 24 24" className="h-8 w-8 text-black" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
                  </svg>
                </div>
                <p className="text-center text-sm text-zinc-500">App Preview Coming Soon</p>
                <div className="mt-8 w-full space-y-3">
                  <div className="h-3 rounded-full bg-zinc-800" />
                  <div className="h-3 w-4/5 rounded-full bg-zinc-800" />
                  <div className="h-3 w-3/5 rounded-full bg-zinc-800" />
                  <div className="mt-6 h-20 rounded-xl bg-zinc-800/50" />
                  <div className="h-20 rounded-xl bg-zinc-800/50" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* App screenshots swiper */}
      <AppScreenshotsSwiper />

      {/* Features */}
      <section id="features" className="relative border-t border-white/5 bg-zinc-950 py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <Badge variant="secondary" className="mb-4 border border-cyan-500/20 bg-cyan-500/10 text-cyan-400">
              Features
            </Badge>
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Everything You Need to
              <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-transparent"> Dominate</span>
            </h2>
            <p className="mt-4 text-lg text-zinc-400">
              From automatic equipment detection to premium supplements -- GearSnitch is built for serious athletes.
            </p>
          </div>

          <div className="mt-16 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {features.map((feature) => (
              <Card
                key={feature.title}
                className="group border-white/5 bg-zinc-900/50 transition-all hover:border-cyan-500/20 hover:bg-zinc-900"
              >
                <CardContent className="p-6">
                  <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br from-cyan-500/20 to-emerald-500/20 text-cyan-400 transition-colors group-hover:from-cyan-500/30 group-hover:to-emerald-500/30">
                    {feature.icon}
                  </div>
                  <h3 className="mb-2 text-lg font-semibold text-white">{feature.title}</h3>
                  <p className="text-sm leading-relaxed text-zinc-400">{feature.description}</p>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section id="how-it-works" className="border-t border-white/5 py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <Badge variant="secondary" className="mb-4 border border-emerald-500/20 bg-emerald-500/10 text-emerald-400">
              How It Works
            </Badge>
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              Get Set Up in
              <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-transparent"> Under 2 Minutes</span>
            </h2>
            <p className="mt-4 text-lg text-zinc-400">
              No complicated setup. No manual logging. Just walk in and train.
            </p>
          </div>

          <div className="mt-16 grid gap-8 md:grid-cols-2 lg:grid-cols-4">
            {steps.map((item, idx) => (
              <div key={item.step} className="relative text-center">
                {/* Connector line (hidden on mobile and last item) */}
                {idx < steps.length - 1 && (
                  <div className="absolute left-[calc(50%+2.5rem)] top-8 hidden h-px w-[calc(100%-5rem)] bg-gradient-to-r from-zinc-800 to-zinc-800/0 lg:block" />
                )}
                <div className="mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-2xl border border-white/10 bg-zinc-900">
                  <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-2xl font-bold text-transparent">
                    {item.step}
                  </span>
                </div>
                <h3 className="mb-2 text-lg font-semibold text-white">{item.title}</h3>
                <p className="text-sm text-zinc-400">{item.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Download CTA */}
      <section id="download" className="border-t border-white/5 py-24">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="relative overflow-hidden rounded-3xl border border-white/5 bg-gradient-to-br from-zinc-900 via-zinc-900 to-zinc-800 p-12 text-center sm:p-16">
            {/* Glow effect */}
            <div className="pointer-events-none absolute inset-0">
              <div className="absolute left-1/2 top-0 h-[300px] w-[500px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-cyan-500/10 blur-3xl" />
            </div>

            <div className="relative">
              <h2 className="text-3xl font-bold tracking-tight sm:text-4xl lg:text-5xl">
                Ready to
                <span className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-transparent"> Snitch</span>?
              </h2>
              <p className="mx-auto mt-4 max-w-xl text-lg text-zinc-400">
                Join thousands of athletes already using GearSnitch to protect their gear,
                track their sessions, and earn rewards.
              </p>

              <div className="mt-8 flex flex-col items-center justify-center gap-4 sm:flex-row">
                <Button size="lg" className="h-14 min-w-[200px] bg-gradient-to-r from-cyan-500 to-emerald-500 text-base font-bold text-black transition-all hover:from-cyan-400 hover:to-emerald-400 hover:shadow-lg hover:shadow-cyan-500/25">
                  <svg viewBox="0 0 24 24" className="mr-2 h-5 w-5" fill="currentColor">
                    <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
                  </svg>
                  Download for iOS
                </Button>
                <Button size="lg" variant="outline" className="h-14 min-w-[200px] border-zinc-700 text-base font-bold text-white hover:border-zinc-500 hover:bg-white/5">
                  <svg viewBox="0 0 24 24" className="mr-2 h-5 w-5" fill="currentColor">
                    <path d="M3.609 1.814L13.792 12 3.61 22.186a.996.996 0 01-.61-.92V2.734a1 1 0 01.609-.92zm10.89 10.893l2.302 2.302-10.937 6.333 8.635-8.635zm3.199-1.4l2.834 1.64a1 1 0 010 1.73l-2.834 1.64-2.532-2.532 2.532-2.478zM5.864 1.469L16.8 7.8l-2.3 2.3-8.636-8.63z"/>
                  </svg>
                  Google Play (Soon)
                </Button>
              </div>

              <p className="mt-6 text-sm text-zinc-600">
                Free to download. Premium features at $29.99/year. Requires iOS 16+.
              </p>
            </div>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
