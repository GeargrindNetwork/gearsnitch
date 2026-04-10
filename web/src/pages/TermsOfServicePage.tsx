import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

export default function TermsOfServicePage() {
  return (
    <div className="min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">Terms of Service</h1>
        <p className="mt-2 text-sm text-zinc-500">Effective Date: April 10, 2026</p>

        <Separator className="my-8 bg-white/5" />

        <div className="space-y-8">
          {/* Acceptance */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">1. Acceptance of Terms</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                By downloading, installing, or using GearSnitch ("the App"), you agree to be
                bound by these Terms of Service ("Terms"). If you do not agree, do not use
                the App. GearSnitch is operated by Geargrind (Shawn Frazier Inc.), a
                Florida-based company.
              </p>
              <p>
                You must be at least 17 years of age to use the App. By using GearSnitch,
                you represent that you meet this requirement.
              </p>
            </CardContent>
          </Card>

          {/* Accounts */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">2. Accounts & Authentication</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch uses OAuth-based authentication via Google and Apple. You are
                responsible for maintaining the security of your linked accounts. We do not
                store your OAuth provider password.
              </p>
              <p>
                You agree to provide accurate information and to keep your account
                credentials secure. You are responsible for all activity that occurs under
                your account.
              </p>
            </CardContent>
          </Card>

          {/* Subscriptions */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">3. Subscriptions & Pricing</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-sm leading-relaxed text-zinc-400">
              <p>GearSnitch offers three subscription tiers:</p>
              <div className="overflow-hidden rounded-lg border border-white/5">
                <table className="w-full text-left">
                  <thead>
                    <tr className="border-b border-white/5 bg-zinc-800/50">
                      <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-zinc-300">
                        Tier
                      </th>
                      <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-zinc-300">
                        Price
                      </th>
                      <th className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-zinc-300">
                        Billing
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr className="border-b border-white/5">
                      <td className="px-4 py-3 font-medium text-cyan-400">HUSTLE</td>
                      <td className="px-4 py-3">$4.99</td>
                      <td className="px-4 py-3">Monthly</td>
                    </tr>
                    <tr className="border-b border-white/5">
                      <td className="px-4 py-3 font-medium text-emerald-400">HWMF</td>
                      <td className="px-4 py-3">$60.00</td>
                      <td className="px-4 py-3">Annually</td>
                    </tr>
                    <tr>
                      <td className="px-4 py-3 font-medium text-amber-400">BABY MOMMA</td>
                      <td className="px-4 py-3">$99.00</td>
                      <td className="px-4 py-3">Lifetime (one-time)</td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <p>
                Subscriptions purchased through the Apple App Store are subject to Apple's
                billing terms, including auto-renewal policies. You can manage or cancel
                subscriptions in your Apple ID settings. Web-based subscriptions are
                processed by Stripe.
              </p>
            </CardContent>
          </Card>

          {/* Refunds */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">4. Refund Policy</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                <span className="font-medium text-zinc-300">App Store purchases:</span>{' '}
                Refunds for subscriptions purchased through the Apple App Store are handled
                exclusively by Apple. To request a refund, visit{' '}
                <a
                  href="https://reportaproblem.apple.com"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-cyan-400 underline hover:text-cyan-300"
                >
                  reportaproblem.apple.com
                </a>
                .
              </p>
              <p>
                <span className="font-medium text-zinc-300">Stripe purchases:</span>{' '}
                Refund requests for web-based purchases must be submitted within 14 days of
                the transaction by emailing{' '}
                <a
                  href="mailto:admin@geargrind.net"
                  className="text-cyan-400 underline hover:text-cyan-300"
                >
                  admin@geargrind.net
                </a>
                . Lifetime subscriptions are non-refundable after 14 days.
              </p>
            </CardContent>
          </Card>

          {/* Peptide Store */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">5. Peptide Store</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch operates an integrated peptide store. All products sold through
                the peptide store are intended{' '}
                <span className="font-semibold text-zinc-200">
                  for research purposes only
                </span>{' '}
                and are not intended for human consumption unless otherwise stated.
              </p>
              <p>
                You must be at least{' '}
                <span className="font-semibold text-zinc-200">21 years of age</span> to
                purchase products from the peptide store. By completing a purchase, you
                confirm that you meet this age requirement.
              </p>
              <p>
                Products sold through the peptide store are{' '}
                <span className="font-semibold text-zinc-200">
                  not evaluated or approved by the FDA
                </span>
                . They are not intended to diagnose, treat, cure, or prevent any disease.
                Geargrind makes no therapeutic claims regarding any products sold.
              </p>
            </CardContent>
          </Card>

          {/* BLE Disclaimer */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">6. BLE Monitoring Disclaimer</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch's Bluetooth Low Energy (BLE) gear monitoring feature is a
                convenience tool designed to help you keep track of your fitness equipment.
                It is{' '}
                <span className="font-semibold text-zinc-200">
                  not a security device or anti-theft system
                </span>
                .
              </p>
              <p>
                BLE signals can be affected by interference, battery levels, distance,
                physical obstructions, and device compatibility. We do not guarantee
                continuous or accurate tracking. Geargrind is not liable for any loss,
                theft, or damage to your equipment.
              </p>
            </CardContent>
          </Card>

          {/* Health Disclaimer */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">7. Health & Fitness Disclaimer</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                GearSnitch provides fitness tracking features for informational purposes
                only. The App is{' '}
                <span className="font-semibold text-zinc-200">
                  not a medical device and does not provide medical advice
                </span>
                . Workout data, health metrics, and fitness recommendations should not be
                used as a substitute for professional medical advice, diagnosis, or
                treatment.
              </p>
              <p>
                Always consult a qualified healthcare provider before starting or modifying
                any fitness program.
              </p>
            </CardContent>
          </Card>

          {/* Prohibited Conduct */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">8. Prohibited Conduct</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>You agree not to:</p>
              <ul className="list-inside list-disc space-y-2 pl-2">
                <li>Use the App for any unlawful purpose</li>
                <li>Reverse engineer, decompile, or disassemble the App</li>
                <li>Attempt to gain unauthorized access to our servers or systems</li>
                <li>Interfere with or disrupt the App or its infrastructure</li>
                <li>
                  Create fake accounts, abuse referral programs, or engage in fraud
                </li>
                <li>
                  Resell peptide store products as consumer goods or make unapproved health
                  claims
                </li>
                <li>Harass, abuse, or harm other users</li>
                <li>Use automated tools to scrape or interact with the App</li>
              </ul>
              <p>
                Violation of these terms may result in immediate account termination without
                notice.
              </p>
            </CardContent>
          </Card>

          {/* Intellectual Property */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">9. Intellectual Property</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                All content, features, and functionality of GearSnitch -- including but not
                limited to text, graphics, logos, icons, images, audio, software, and the
                underlying code -- are the exclusive property of Geargrind (Shawn Frazier
                Inc.) and are protected by United States and international copyright,
                trademark, and intellectual property laws.
              </p>
              <p>
                The GearSnitch name, logo, and all related marks are trademarks of
                Geargrind. You may not use them without prior written consent.
              </p>
            </CardContent>
          </Card>

          {/* Limitation of Liability */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">10. Limitation of Liability</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                TO THE MAXIMUM EXTENT PERMITTED BY LAW, GEARGRIND (SHAWN FRAZIER INC.)
                SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR
                PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF PROFITS, DATA, USE,
                OR GOODWILL, ARISING OUT OF OR RELATED TO YOUR USE OF THE APP.
              </p>
              <p>
                OUR TOTAL LIABILITY FOR ANY CLAIMS ARISING UNDER THESE TERMS SHALL NOT
                EXCEED THE AMOUNT YOU PAID TO US IN THE TWELVE (12) MONTHS PRECEDING THE
                CLAIM.
              </p>
              <p>
                THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY
                KIND, EXPRESS OR IMPLIED.
              </p>
            </CardContent>
          </Card>

          {/* Governing Law */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">11. Governing Law</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                These Terms shall be governed by and construed in accordance with the laws
                of the State of Florida, United States, without regard to conflict of law
                principles. Any disputes arising from these Terms or your use of the App
                shall be resolved exclusively in the state or federal courts located in
                Florida.
              </p>
            </CardContent>
          </Card>

          {/* Changes */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">12. Changes to Terms</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                We reserve the right to modify these Terms at any time. Material changes
                will be communicated via the App or email. Continued use of the App after
                changes constitutes acceptance of the updated Terms.
              </p>
            </CardContent>
          </Card>

          {/* Contact */}
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">13. Contact</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
              <p>
                For questions about these Terms, contact us at:
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
