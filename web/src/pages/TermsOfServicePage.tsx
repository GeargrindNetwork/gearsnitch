import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

const EFFECTIVE_DATE = '2026-04-18';
const SUPPORT_EMAIL = 'support@gearsnitch.com';
const GOVERNING_STATE = '[STATE], USA — confirm';

export default function TermsOfServicePage() {
  return (
    <div className="dark min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">
          Terms of Service
        </h1>
        <p className="mt-2 text-sm text-zinc-500">
          Last updated: {EFFECTIVE_DATE}
        </p>
        <p className="mt-4 max-w-3xl text-sm leading-relaxed text-zinc-400">
          These Terms of Service (&quot;Terms&quot;) form a binding agreement
          between you and GearSnitch governing your use of the GearSnitch
          mobile app, the website at{' '}
          <span className="text-zinc-200">www.gearsnitch.com</span>,
          subscriptions, the in-app store, and any related services.
        </p>

        <Separator className="my-8 bg-white/5" />

        <div className="space-y-8">
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">1. Acceptance of Terms</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                By creating an account, installing the app, or otherwise using
                GearSnitch you agree to these Terms and to our{' '}
                <a
                  href="/privacy"
                  className="text-cyan-400 underline hover:text-cyan-300"
                >
                  Privacy Policy
                </a>
                . If you do not agree, do not use the service.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                2. Description of Service
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch is a fitness companion that lets you track workouts
                and runs, log gear usage, monitor paired Bluetooth devices,
                and keep a personal journal of peptides, supplements, and
                medications you take. The in-app store sells related physical
                and digital goods.
              </p>
              <p className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 text-amber-200">
                GearSnitch is <span className="font-semibold">not a medical
                device</span>, is <span className="font-semibold">not
                diagnostic</span>, and is <span className="font-semibold">not
                a substitute for professional medical advice, diagnosis, or
                treatment</span>. Always consult a licensed healthcare provider
                before starting, stopping, or changing any medication or
                regimen. In an emergency call your local emergency number.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                3. Account and Eligibility
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>You must be at least 13 years old to use GearSnitch.</li>
                <li>
                  You must provide accurate registration information and keep
                  it current.
                </li>
                <li>
                  You are responsible for safeguarding your password and any
                  activity under your account.
                </li>
                <li>
                  One account per person. Sharing or reselling accounts is
                  prohibited.
                </li>
                <li>
                  Notify us immediately at{' '}
                  <a
                    href={`mailto:${SUPPORT_EMAIL}`}
                    className="text-cyan-400 underline hover:text-cyan-300"
                  >
                    {SUPPORT_EMAIL}
                  </a>{' '}
                  if you suspect unauthorized use of your account.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                4. Subscriptions and Payments
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                Some features require a paid subscription. Subscriptions
                renew automatically at the end of each billing period at the
                then-current rate unless cancelled at least 24 hours before
                renewal.
              </p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  <span className="text-zinc-200">Apple-billed
                  subscriptions:</span> manage and cancel via{' '}
                  <span className="text-zinc-200">
                    Settings &rarr; Apple ID &rarr; Subscriptions
                  </span>{' '}
                  on your iPhone or iPad. Refunds are handled exclusively by
                  Apple per the Apple Media Services Terms.
                </li>
                <li>
                  <span className="text-zinc-200">Stripe-billed
                  subscriptions:</span> manage payment methods and cancel via
                  the Stripe Customer Portal accessible from your GearSnitch
                  account page. Refund policy follows Stripe defaults; contact
                  support for prorated edge cases.
                </li>
                <li>
                  In-app purchases of physical goods from the store are subject
                  to the order, shipping, and return terms shown at checkout.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">5. Acceptable Use</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>You agree not to:</p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>
                  scrape, crawl, or systematically harvest data from the
                  service;
                </li>
                <li>
                  reverse-engineer, decompile, or disassemble the app except
                  where applicable law expressly permits it;
                </li>
                <li>
                  attempt to gain unauthorized access to accounts, servers, or
                  networks;
                </li>
                <li>
                  resell, sublicense, or commercially exploit the service
                  without our written consent;
                </li>
                <li>
                  use the service to harass, defraud, or harm other users;
                </li>
                <li>
                  upload content that infringes intellectual-property or
                  privacy rights, or that violates applicable law.
                </li>
              </ul>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                6. Intellectual Property
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                The GearSnitch app, website, brand, source code, and all
                accompanying content are owned by us or our licensors and are
                protected by copyright, trademark, and other intellectual
                property laws. You receive a limited, non-exclusive,
                non-transferable, revocable license to use the service for its
                intended purpose.
              </p>
              <p>
                You retain ownership of the content you upload (workouts,
                medication logs, photos, notes). You grant us a worldwide,
                royalty-free license to host, store, transmit, back up, and
                display that content solely to operate and improve the service
                for you.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                7. Disclaimer of Warranties
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                THE SERVICE IS PROVIDED <span className="text-zinc-200">&quot;AS
                IS&quot;</span> AND <span className="text-zinc-200">&quot;AS
                AVAILABLE&quot;</span> WITHOUT WARRANTIES OF ANY KIND, WHETHER
                EXPRESS, IMPLIED, OR STATUTORY, INCLUDING IMPLIED WARRANTIES
                OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
                NON-INFRINGEMENT. WE MAKE NO MEDICAL CLAIMS AND DO NOT
                WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE,
                OR ACCURATE.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">
                8. Limitation of Liability
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                To the maximum extent permitted by law, GearSnitch and its
                officers, employees, and contractors will not be liable for any
                indirect, incidental, special, consequential, exemplary, or
                punitive damages, or for lost profits, lost revenue, lost data,
                or business interruption arising out of or related to your use
                of the service.
              </p>
              <p>
                Our aggregate liability for any claim arising from these Terms
                or the service is capped at the amounts you paid us during the
                12 months preceding the event giving rise to the claim, or
                US $100, whichever is greater.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">9. Indemnification</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                You agree to indemnify, defend, and hold harmless GearSnitch
                and its officers, employees, and contractors from any claim,
                liability, loss, damage, or expense (including reasonable
                attorneys&apos; fees) arising out of or related to your
                violation of these Terms, your misuse of the service, or your
                violation of any law or third-party right.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">10. Governing Law</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                These Terms are governed by the laws of {GOVERNING_STATE},
                without regard to its conflict-of-laws principles. Any dispute
                arising out of these Terms or your use of the service will be
                brought exclusively in the state or federal courts located in
                that jurisdiction, unless applicable law requires otherwise.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">11. Changes to Terms</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We may update these Terms from time to time. When we make
                material changes we will revise the &quot;Last updated&quot;
                date above and, where appropriate, give you notice in-app or
                by email. Continued use of GearSnitch after the changes take
                effect means you accept the revised Terms.
              </p>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">12. Contact</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>For questions about these Terms, contact us at:</p>
              <div className="mt-2 rounded-lg bg-zinc-800/50 p-4">
                <p className="font-medium text-zinc-200">GearSnitch Legal</p>
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
