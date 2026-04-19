import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

const EFFECTIVE_DATE = '2026-04-18';
const SUPPORT_EMAIL = 'support@gearsnitch.com';

export default function PrivacyPolicyPage() {
  return (
    <div className="dark min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">
          Privacy Policy
        </h1>
        <p className="mt-2 text-sm text-zinc-500">
          Last updated: {EFFECTIVE_DATE}
        </p>
        <p className="mt-4 max-w-3xl text-sm leading-relaxed text-zinc-400">
          This Privacy Policy describes the personal data that GearSnitch
          (&quot;GearSnitch,&quot; &quot;we,&quot; &quot;our,&quot; or
          &quot;us&quot;) collects when you use the GearSnitch iOS app, the
          GearSnitch website at{' '}
          <span className="text-zinc-200">www.gearsnitch.com</span>, and any
          related services. It enumerates every data category we collect, why
          we collect it, who we share it with, how long we keep it, and the
          rights you have over it. This policy is intended to satisfy Apple
          App Store Review Guideline 5.1 and the App Privacy disclosures in
          App Store Connect.
        </p>

        <Separator className="my-8 bg-white/5" />

        <div className="space-y-8">
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Data We Collect</CardTitle>
            </CardHeader>
            <CardContent className="space-y-5 text-sm leading-relaxed text-zinc-400">
              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Account data
                </h3>
                <ul className="list-inside list-disc space-y-1 pl-2">
                  <li>Email address</li>
                  <li>Hashed password (bcrypt; we never store plaintext)</li>
                  <li>Display name</li>
                  <li>Optional profile photo</li>
                  <li>
                    Sign-in-with-Apple / Sign-in-with-Google identifier when
                    you use those providers
                  </li>
                </ul>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Health and fitness data
                </h3>
                <ul className="list-inside list-disc space-y-1 pl-2">
                  <li>
                    Heart rate read from paired BLE devices, AirPods, Apple
                    Watch, and Powerbeats Pro 2
                  </li>
                  <li>
                    Workouts (type, duration, distance, calories, perceived
                    effort)
                  </li>
                  <li>
                    Runs, including GPS polylines if you choose to share a run
                  </li>
                  <li>Gym sessions and gear-usage logs</li>
                  <li>
                    ECG readings (read-only, surfaced from Apple HealthKit when
                    you grant permission)
                  </li>
                </ul>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Medication and supplement data
                </h3>
                <p>
                  Doses, schedules, and notes for peptides, supplements, and
                  medications you log inside GearSnitch. On iOS 18.4 and later
                  this data is bidirectionally synced with the Apple Health
                  Medications database when you opt in. We do not infer
                  diagnoses from this data and we do not share it with any
                  advertiser, broker, or insurer.
                </p>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Location data
                </h3>
                <p>
                  Precise location is used only to detect when you arrive at a
                  saved gym (geofence check-in). GearSnitch does not track
                  location continuously in the background and does not build a
                  location history outside the gym-session record.
                </p>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Bluetooth data
                </h3>
                <p>
                  Bluetooth Low Energy device identifiers (UUIDs / MAC-derived
                  IDs) and RSSI signal-strength trends for gear you have paired
                  with the app. Used for connection state, separation alerts,
                  and battery diagnostics.
                </p>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Payment data
                </h3>
                <ul className="list-inside list-disc space-y-1 pl-2">
                  <li>Subscription tier and renewal status</li>
                  <li>
                    Apple StoreKit transaction IDs for in-app purchases
                  </li>
                  <li>
                    Stripe customer ID and the last four digits of your card
                    (issued by Stripe; we never receive the full PAN, expiry,
                    or CVV)
                  </li>
                </ul>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Referral data
                </h3>
                <ul className="list-inside list-disc space-y-1 pl-2">
                  <li>
                    <code className="rounded bg-zinc-800 px-1 py-0.5 text-zinc-200">
                      gs_ref
                    </code>{' '}
                    attribution cookie (HttpOnly, SameSite=Lax, 30-day expiry)
                  </li>
                  <li>
                    A <code className="rounded bg-zinc-800 px-1 py-0.5 text-zinc-200">user.referredBy</code>{' '}
                    reference linking you to the user who invited you
                  </li>
                </ul>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Device and diagnostic data
                </h3>
                <ul className="list-inside list-disc space-y-1 pl-2">
                  <li>Apple Push Notification service (APNs) device token</li>
                  <li>App version, OS version, device model</li>
                  <li>
                    Crash logs and non-fatal error reports (no screen
                    recordings, no keystrokes)
                  </li>
                </ul>
              </div>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                Data We Do Not Collect
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  No cross-site web-tracking identifiers and no advertising
                  identifier (IDFA).
                </li>
                <li>
                  No third-party SDK that sells, brokers, or monetizes your
                  data.
                </li>
                <li>
                  No microphone audio, camera frames, or screen recordings.
                </li>
                <li>
                  No contacts, calendar entries, photos, or files outside the
                  ones you explicitly attach.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">How We Use It</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  <span className="text-zinc-200">App functionality:</span>{' '}
                  authenticate you, sync workouts and gear, deliver alerts,
                  process subscriptions, and run referral rewards.
                </li>
                <li>
                  <span className="text-zinc-200">Customer support:</span>{' '}
                  diagnose tickets you send to our support inbox or in-app
                  support form.
                </li>
                <li>
                  <span className="text-zinc-200">
                    Product analytics (aggregate):
                  </span>{' '}
                  measure feature adoption, performance, and crash rate. We
                  use first-party event logging only.
                </li>
                <li>
                  <span className="text-zinc-200">Legal compliance:</span>{' '}
                  fulfill tax, accounting, fraud-prevention, and lawful-request
                  obligations.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                Sharing and Third Parties
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm leading-relaxed text-zinc-400">
              <p>
                We share the minimum data needed to operate the service. The
                vendors below are processors acting on our instructions:
              </p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  <span className="text-zinc-200">Apple Inc.</span> &mdash;
                  receives APNs push tokens to deliver notifications and
                  StoreKit transaction data when you make in-app purchases.
                  Apple HealthKit data stays on your device unless you
                  explicitly export it.
                </li>
                <li>
                  <span className="text-zinc-200">Stripe, Inc.</span> &mdash;
                  processes credit-card subscription payments. Stripe receives
                  your name, email, billing address, and payment-instrument
                  data directly; we receive only the customer ID, last-4, card
                  brand, and transaction status.
                </li>
                <li>
                  <span className="text-zinc-200">Cloud hosting providers</span>{' '}
                  storing encrypted database records, log files, and backups.
                </li>
                <li>
                  <span className="text-zinc-200">
                    HIPAA-covered partners (when applicable):
                  </span>{' '}
                  any vendor that touches health data is bound by a Business
                  Associate Agreement before any transfer occurs.
                </li>
              </ul>
              <p>
                We do not share your personal data with advertisers, data
                brokers, or social networks. We do not sell personal data and
                we do not engage in cross-context behavioral advertising as
                those terms are defined under the CCPA and equivalent laws.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Retention</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  <span className="text-zinc-200">Active subscribers:</span>{' '}
                  account and content data retained for as long as your
                  account remains active.
                </li>
                <li>
                  <span className="text-zinc-200">Cancelled accounts:</span>{' '}
                  data is purged within 90 days of cancellation, except where
                  retention is required for legal, tax, or fraud-prevention
                  reasons.
                </li>
                <li>
                  <span className="text-zinc-200">Per-row content:</span>{' '}
                  workouts, runs, gym sessions, and medication logs are kept
                  until you delete them individually.
                </li>
                <li>
                  <span className="text-zinc-200">Backups:</span> encrypted
                  backups roll off within 35 days.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Your Rights</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  <span className="text-zinc-200">Access and export:</span>{' '}
                  email{' '}
                  <a
                    href={`mailto:${SUPPORT_EMAIL}`}
                    className="text-cyan-400 underline hover:text-cyan-300"
                  >
                    {SUPPORT_EMAIL}
                  </a>{' '}
                  to receive a machine-readable export of your data.
                </li>
                <li>
                  <span className="text-zinc-200">Deletion:</span> use the
                  in-app path Account &rarr; Delete Account, or visit{' '}
                  <a
                    href="/delete-account"
                    className="text-cyan-400 underline hover:text-cyan-300"
                  >
                    /delete-account
                  </a>
                  .
                </li>
                <li>
                  <span className="text-zinc-200">Correction:</span> update
                  most fields in-app; email support for anything you cannot
                  edit yourself.
                </li>
                <li>
                  <span className="text-zinc-200">
                    Withdraw consent / opt out:
                  </span>{' '}
                  revoke HealthKit, Bluetooth, location, or notification
                  permissions in iOS Settings at any time.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                Children&apos;s Privacy
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch is rated for users aged 13 and up. We do not
                knowingly collect personal data from anyone under 13, and the
                service is not intended to be used by children under that age.
                If you believe a child under 13 has provided personal data to
                us, contact{' '}
                <a
                  href={`mailto:${SUPPORT_EMAIL}`}
                  className="text-cyan-400 underline hover:text-cyan-300"
                >
                  {SUPPORT_EMAIL}
                </a>{' '}
                and we will delete it.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Security</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                Data in transit is protected with TLS 1.2+. Passwords are
                hashed with bcrypt. Database backups and at-rest storage are
                encrypted. Access to production systems is restricted to a
                small set of named operators.
              </p>
              <p>
                No system is perfectly secure. Use a strong, unique password
                and enable platform-level protections (Face ID, device
                passcode) on your phone.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                Changes to This Policy
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                When we make material changes we will revise the &quot;Last
                updated&quot; date above and, where required by law, give you
                advance notice. Continued use of GearSnitch after the changes
                take effect means you accept the revised policy.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Contact</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                For privacy questions, data-export requests, or complaints,
                email us:
              </p>
              <div className="mt-2 rounded-lg bg-zinc-800/50 p-4">
                <p className="font-medium text-zinc-200">GearSnitch Privacy</p>
                <p>
                  Email:{' '}
                  <a
                    href={`mailto:${SUPPORT_EMAIL}`}
                    className="text-cyan-400 underline hover:text-cyan-300"
                  >
                    {SUPPORT_EMAIL}
                  </a>
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      </main>

      <Footer />
    </div>
  );
}
