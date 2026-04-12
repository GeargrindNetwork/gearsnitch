import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

const EFFECTIVE_DATE = 'April 10, 2026';
const SUPPORT_EMAIL = 'support@gearsnitch.com';

export default function PrivacyPolicyPage() {
  return (
    <div className="min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">
          Privacy Policy
        </h1>
        <p className="mt-2 text-sm text-zinc-500">
          Effective Date: {EFFECTIVE_DATE}
        </p>
        <p className="mt-4 max-w-3xl text-sm leading-relaxed text-zinc-400">
          This Privacy Policy explains how GearSnitch collects, uses, shares,
          and protects information when you use{' '}
          <span className="text-zinc-200">www.gearsnitch.com</span>, the
          GearSnitch mobile application, and related products or support
          services. It is intended to serve as the public privacy policy linked
          from both the website and the application.
        </p>

        <Separator className="my-8 bg-white/5" />

        <div className="space-y-8">
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Who We Are</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch (&quot;GearSnitch,&quot; &quot;we,&quot; &quot;our,&quot; or
                &quot;us&quot;) operates the GearSnitch website, app, and
                supporting services. This policy describes how we handle
                personal information that relates to those services.
              </p>
              <p>
                By accessing or using GearSnitch, you acknowledge this Privacy
                Policy. If you do not agree with it, do not use the service.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                Information We Collect
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm leading-relaxed text-zinc-400">
              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Account and identity information
                </h3>
                <p>
                  When you create or use a GearSnitch account, we may collect
                  your email address, display name, profile image, account
                  identifier, and login-provider details. If you sign in with
                  Apple or Google, we receive the information those providers
                  make available to us, such as your name, email address, and
                  provider account identifier.
                </p>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Device, app, and log information
                </h3>
                <p>
                  We collect technical information needed to operate and secure
                  the service, including device type, operating system, app
                  version, browser or user agent, IP address, request logs,
                  session identifiers, and crash or diagnostic events.
                </p>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Fitness, gear, and feature data
                </h3>
                <p>
                  Depending on the features you use, we may collect Bluetooth
                  device identifiers, workout or activity records, gym or
                  geofence data, notification preferences, emergency contact
                  information, nutrition or health-related entries you provide,
                  and similar account-linked content needed to deliver the app.
                </p>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Location and permission-based data
                </h3>
                <p>
                  If you grant permission, GearSnitch may use foreground or
                  background location information and Bluetooth access to power
                  monitoring, gym detection, alerts, or related features. These
                  permissions are optional, but some features may not work
                  without them.
                </p>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Purchases and subscription information
                </h3>
                <p>
                  If you purchase subscriptions or products, we receive order,
                  billing, subscription, fulfillment, and transaction metadata.
                  Payment card details are typically processed by payment
                  providers and are not stored by GearSnitch in full.
                </p>
              </div>

              <div>
                <h3 className="mb-2 font-semibold text-zinc-200">
                  Support and communications
                </h3>
                <p>
                  If you contact us, complete a form, or respond to a support
                  request, we collect the information you choose to provide,
                  such as your name, email address, and message contents.
                </p>
              </div>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                How We Use Information
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>We use personal information to:</p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>create and maintain user accounts;</li>
                <li>authenticate users and link sign-in providers;</li>
                <li>deliver app, website, store, and support functionality;</li>
                <li>
                  process orders, subscriptions, renewals, cancellations, and
                  refunds;
                </li>
                <li>
                  send service communications, alerts, support responses, and
                  security notices;
                </li>
                <li>
                  analyze usage, troubleshoot issues, and improve the service;
                </li>
                <li>protect against fraud, abuse, and unauthorized access;</li>
                <li>
                  comply with legal obligations and enforce our agreements.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                When We Share Information
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We may share information with service providers that help us run
                GearSnitch, such as hosting, analytics, payment, customer
                support, communications, and infrastructure vendors.
              </p>
              <p>
                We may also disclose information when reasonably necessary to
                comply with the law, respond to legal requests, investigate
                misuse, protect our users or business, or as part of a merger,
                acquisition, financing, or asset sale.
              </p>
              <p>
                GearSnitch does not sell personal information for money. We also
                do not knowingly share personal information for cross-context
                behavioral advertising.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                Cookies, Analytics, and Similar Technologies
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                Our website and services may use cookies, local storage,
                session tokens, and analytics tools to remember your session,
                understand performance, secure the service, and improve the
                experience.
              </p>
              <p>
                You can usually control cookies through your browser settings
                and control app permissions through your device settings.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Data Retention</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We retain information for as long as reasonably necessary to
                provide the service, maintain your account, comply with legal
                obligations, resolve disputes, and enforce our agreements.
              </p>
              <p>
                Retention periods vary by data type. For example, account and
                purchase records may be retained longer than temporary session
                or cache data. When data is no longer needed, we delete or
                de-identify it where practical.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                Your Choices and Privacy Rights
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                Depending on where you live, you may have rights to access,
                correct, delete, export, or limit certain uses of your personal
                information. You may also have the right to opt out of certain
                communications.
              </p>
              <p>
                You can request account deletion through our{' '}
                <a
                  href="/delete-account"
                  className="text-cyan-400 underline hover:text-cyan-300"
                >
                  Delete Account
                </a>{' '}
                page or by contacting us. We may need to keep limited
                information where required for security, fraud prevention,
                accounting, or legal compliance.
              </p>
              <p>
                To make a privacy request, email{' '}
                <a
                  href={`mailto:${SUPPORT_EMAIL}`}
                  className="text-cyan-400 underline hover:text-cyan-300"
                >
                  {SUPPORT_EMAIL}
                </a>
                .
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Security</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We use administrative, technical, and organizational safeguards
                designed to protect personal information. These may include
                encryption in transit, access controls, authentication tokens,
                monitoring, and vendor security measures.
              </p>
              <p>
                No system is perfectly secure, and we cannot guarantee absolute
                security. You should also protect your own devices, accounts,
                and login credentials.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Children&apos;s Privacy</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch is not directed to children under 13, and we do not
                knowingly collect personal information from them. If you believe
                a child has provided personal information to us, contact us so
                we can investigate and take appropriate action.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Changes to This Policy</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We may update this Privacy Policy from time to time. If we make
                material changes, we will post the updated version here and
                revise the effective date above. Your continued use of
                GearSnitch after the update takes effect means the revised
                policy applies to your future use.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Contact Us</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                For privacy questions, requests, or complaints, contact us at:
              </p>
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
