import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

const EFFECTIVE_DATE = 'April 10, 2026';
const SUPPORT_EMAIL = 'support@gearsnitch.com';

export default function TermsOfServicePage() {
  return (
    <div className="min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">
          Terms of Service
        </h1>
        <p className="mt-2 text-sm text-zinc-500">
          Effective Date: {EFFECTIVE_DATE}
        </p>
        <p className="mt-4 max-w-3xl text-sm leading-relaxed text-zinc-400">
          These Terms of Service govern your use of{' '}
          <span className="text-zinc-200">www.gearsnitch.com</span>, the
          GearSnitch mobile application, and any related services, products, or
          support channels we make available.
        </p>

        <Separator className="my-8 bg-white/5" />

        <div className="space-y-8">
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                1. Acceptance of These Terms
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                By accessing or using GearSnitch, you agree to these Terms of
                Service and our{' '}
                <a
                  href="/privacy"
                  className="text-cyan-400 underline hover:text-cyan-300"
                >
                  Privacy Policy
                </a>
                . If you do not agree, do not use the service.
              </p>
              <p>
                If you use GearSnitch on behalf of an organization, you
                represent that you have authority to bind that organization to
                these Terms.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                2. Eligibility and Accounts
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                You must be legally capable of entering into a binding agreement
                to use GearSnitch. You are responsible for the accuracy of the
                information associated with your account and for maintaining the
                confidentiality of your login credentials and linked identity
                providers.
              </p>
              <p>
                You are responsible for all activity that occurs under your
                account. Notify us promptly if you believe your account has been
                compromised.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                3. Services, Features, and Availability
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch provides software and related services for gear
                tracking, account management, notifications, commerce, support,
                and other features we may offer from time to time.
              </p>
              <p>
                We may add, remove, suspend, or modify features at any time. We
                do not guarantee that every feature will always be available,
                error-free, or supported on every device or in every region.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                4. Payments, Orders, and Subscriptions
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                Certain GearSnitch features, subscriptions, or products may
                require payment. Pricing, billing frequency, trial terms,
                renewal terms, shipping details, and refund rules will be
                disclosed in the app, on the website, or at checkout.
              </p>
              <p>
                Purchases made through third-party platforms, such as the Apple
                App Store, are also subject to those platforms&apos; terms and
                billing rules. We are not responsible for third-party billing
                workflows outside our control.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                5. Health, Fitness, and Device Disclaimers
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch may include fitness, monitoring, alerting, location,
                Bluetooth, or related convenience features. These tools are
                provided for informational and operational purposes only.
              </p>
              <p>
                GearSnitch is not medical advice, not a medical provider, and
                not a guaranteed security or anti-theft system. Device signals,
                location services, operating systems, batteries, wireless
                conditions, and user permissions can all affect performance.
              </p>
              <p>
                You are responsible for using the service safely and for seeking
                professional advice where needed.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                6. Acceptable Use
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>You agree not to:</p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>use GearSnitch for unlawful, fraudulent, or abusive purposes;</li>
                <li>attempt to access systems or data without authorization;</li>
                <li>
                  interfere with the operation, integrity, or security of the
                  service;
                </li>
                <li>
                  reverse engineer, scrape, copy, or exploit the service except
                  as allowed by law;
                </li>
                <li>misrepresent your identity or create fake accounts;</li>
                <li>
                  upload or transmit content that infringes rights or violates
                  applicable law.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                7. Intellectual Property
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch, including its software, content, branding, design,
                text, graphics, interfaces, and related materials, is owned by
                us or our licensors and protected by applicable intellectual
                property laws.
              </p>
              <p>
                Subject to these Terms, we grant you a limited, non-exclusive,
                non-transferable, revocable right to use the service for its
                intended purpose.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                8. Third-Party Services
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch may integrate with third-party identity, payment,
                analytics, hosting, device, health, or communications services.
                Your use of those third-party services may be subject to their
                own terms and privacy policies.
              </p>
              <p>
                We are not responsible for third-party services, content, or
                policies except as required by law.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                9. Suspension and Termination
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We may suspend or terminate access to GearSnitch if you violate
                these Terms, create risk for the service or other users, fail to
                pay amounts due, or if we decide to discontinue part or all of
                the service.
              </p>
              <p>
                You may stop using the service at any time and may request
                account deletion through our website or support channel.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                10. Disclaimers
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                To the maximum extent permitted by law, GearSnitch is provided
                &quot;as is&quot; and &quot;as available&quot; without warranties of
                any kind, whether express, implied, or statutory, including
                implied warranties of merchantability, fitness for a particular
                purpose, title, and non-infringement.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                11. Limitation of Liability
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                To the maximum extent permitted by law, we will not be liable
                for indirect, incidental, special, consequential, exemplary, or
                punitive damages, or for loss of profits, revenues, data,
                goodwill, or business opportunities arising out of or related to
                your use of GearSnitch.
              </p>
              <p>
                If we are found liable for any claim arising from these Terms or
                the service, our total liability will not exceed the greater of
                the amount you paid us in the 12 months before the claim arose
                or one hundred U.S. dollars (US $100).
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                12. Governing Law
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                These Terms are governed by the laws of the State of Florida,
                excluding conflict-of-law rules. Any dispute arising from these
                Terms or your use of GearSnitch will be brought in the state or
                federal courts located in Florida, unless applicable law
                requires otherwise.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                13. Changes to These Terms
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We may update these Terms from time to time. If we make
                material changes, we will post the updated version here and
                revise the effective date above. Your continued use of the
                service after the updated Terms become effective means you
                accept them.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">14. Contact</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>For questions about these Terms, contact us at:</p>
              <div className="mt-2 rounded-lg bg-zinc-800/50 p-4">
                <p className="font-medium text-zinc-200">GearSnitch Support</p>
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
