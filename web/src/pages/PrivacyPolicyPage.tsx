import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

export default function PrivacyPolicyPage() {
  return (
    <div className="min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">Privacy Policy</h1>
        <p className="mt-2 text-sm text-zinc-500">Effective Date: April 10, 2026</p>

        <Separator className="my-8 bg-white/5" />

        <div className="space-y-8">
          {/* Introduction */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Introduction</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch ("the App") is operated by Geargrind (Shawn Frazier Inc.), a
                Florida-based company ("we," "us," or "our"). This Privacy Policy explains
                how we collect, use, disclose, and protect your personal information when you
                use the GearSnitch mobile application and associated web services.
              </p>
              <p>
                By using GearSnitch, you agree to the collection and use of information in
                accordance with this policy. If you do not agree, please do not use the App.
              </p>
            </CardContent>
          </Card>

          {/* Data We Collect */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Data We Collect</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm leading-relaxed text-zinc-400">
              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">Account Information</h3>
                <p>
                  When you sign in via Google or Apple OAuth, we receive your name, email
                  address, and profile picture. We do not receive or store your OAuth provider
                  password.
                </p>
              </div>
              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">Location Data</h3>
                <p>
                  GearSnitch uses foreground and background location services to detect when
                  you arrive at or leave a partnered gym (geo-fencing). Location data is
                  processed on-device and used to trigger session tracking. We do not
                  continuously track or store your precise GPS coordinates on our servers.
                </p>
              </div>
              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">Bluetooth (BLE) Data</h3>
                <p>
                  The App scans for nearby Bluetooth Low Energy (BLE) devices to monitor your
                  fitness gear. Device identifiers (UUIDs) are stored locally on your device
                  and synced to your account so you can receive disconnect alerts.
                </p>
              </div>
              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">HealthKit Data</h3>
                <p>
                  If you grant permission, GearSnitch reads and writes workout data via Apple
                  HealthKit. HealthKit data is never sold, shared with third parties for
                  advertising, or used for purposes other than providing the App's fitness
                  features to you.
                </p>
              </div>
              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">Purchase & Subscription Data</h3>
                <p>
                  When you subscribe or purchase items from the peptide store, payment
                  processing is handled by Apple (App Store) or Stripe. We receive
                  transaction confirmation details (amount, subscription tier, timestamps)
                  but never your full credit card number.
                </p>
              </div>
              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">Device & Usage Data</h3>
                <p>
                  We collect anonymized analytics data including device type, OS version, app
                  version, session duration, and feature usage to improve the App. This data
                  is collected via Google Analytics and is not linked to your identity.
                </p>
              </div>
            </CardContent>
          </Card>

          {/* Third-Party Services */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Third-Party Services</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>GearSnitch integrates with the following third-party services:</p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  <span className="font-medium text-zinc-300">Google</span> — OAuth
                  authentication and Google Analytics for anonymized usage metrics.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Apple</span> — Sign in with
                  Apple, HealthKit integration, and App Store subscription billing.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Stripe</span> — Payment
                  processing for web-based subscriptions and peptide store purchases.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">MongoDB Atlas</span> — Cloud
                  database hosting for account and application data. Data encrypted at rest
                  (AES-256) and in transit (TLS 1.2+).
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Redis (Upstash)</span> —
                  Session management, rate limiting, and caching. No persistent personal data
                  stored.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Google Cloud Platform (GCP)</span> —
                  API hosting, Cloud Run, and logging infrastructure.
                </li>
              </ul>
              <p>
                Each third-party provider operates under its own privacy policy. We
                encourage you to review them.
              </p>
            </CardContent>
          </Card>

          {/* Data Retention */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Data Retention</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  <span className="font-medium text-zinc-300">Account data</span> is
                  retained until you request deletion of your account.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Session tokens</span> expire
                  after 30 days of inactivity and are automatically purged.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">BLE device data</span> is
                  removed when you delete a tracked device or your account.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">HealthKit data</span> remains
                  in Apple Health and is not stored on our servers.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Analytics data</span> is
                  anonymized and retained for up to 26 months per Google Analytics policies.
                </li>
              </ul>
            </CardContent>
          </Card>

          {/* Your Rights */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Your Rights (GDPR / CCPA)</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                Depending on your jurisdiction, you may have the following rights regarding
                your personal data:
              </p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  <span className="font-medium text-zinc-300">Right to Access</span> — You
                  can request a copy of all personal data we hold about you.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Right to Deletion</span> —
                  You can request that we permanently delete your account and all associated
                  data. Use the{' '}
                  <a href="/delete-account" className="text-cyan-400 underline hover:text-cyan-300">
                    Delete Account
                  </a>{' '}
                  page or email us directly.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Right to Export</span> — You
                  can request a machine-readable export of your data (JSON format).
                </li>
                <li>
                  <span className="font-medium text-zinc-300">Right to Opt Out</span> — You
                  can opt out of non-essential data collection by disabling analytics in the
                  App settings.
                </li>
                <li>
                  <span className="font-medium text-zinc-300">
                    Right to Non-Discrimination
                  </span>{' '}
                  — We will not discriminate against you for exercising your privacy rights.
                </li>
              </ul>
              <p>
                To exercise any of these rights, email us at{' '}
                <a
                  href="mailto:admin@geargrind.net"
                  className="text-cyan-400 underline hover:text-cyan-300"
                >
                  admin@geargrind.net
                </a>
                . We will respond within 30 days.
              </p>
            </CardContent>
          </Card>

          {/* Data Security */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Data Security</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We implement industry-standard security measures including:
              </p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>TLS 1.2+ encryption for all data in transit</li>
                <li>AES-256 encryption for data at rest (MongoDB Atlas)</li>
                <li>JWT-based authentication with short-lived access tokens</li>
                <li>Rate limiting and brute-force protection</li>
                <li>Regular security audits and dependency scanning</li>
              </ul>
              <p>
                No method of electronic transmission or storage is 100% secure. While we
                strive to protect your data, we cannot guarantee absolute security.
              </p>
            </CardContent>
          </Card>

          {/* Children */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Children's Privacy</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch is intended for users aged 17 and older. We do not knowingly
                collect personal information from anyone under the age of 17. If we become
                aware that a user under 17 has provided us with personal data, we will
                delete that information immediately.
              </p>
            </CardContent>
          </Card>

          {/* Changes */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Changes to This Policy</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We may update this Privacy Policy from time to time. We will notify you of
                material changes by posting the new policy on this page and updating the
                "Effective Date" above. Continued use of the App after changes constitutes
                acceptance of the revised policy.
              </p>
            </CardContent>
          </Card>

          {/* Contact */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Contact Us</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                If you have questions about this Privacy Policy, contact us at:
              </p>
              <div className="mt-2 rounded-lg bg-zinc-800/50 p-4">
                <p className="font-medium text-zinc-200">Geargrind (Shawn Frazier Inc.)</p>
                <p>
                  Email:{' '}
                  <a
                    href="mailto:admin@geargrind.net"
                    className="text-cyan-400 underline hover:text-cyan-300"
                  >
                    admin@geargrind.net
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
