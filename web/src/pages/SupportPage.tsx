import { useState } from 'react';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';

const SUPPORT_EMAIL = 'support@gearsnitch.com';
const BUG_EMAIL = 'support@gearsnitch.com';
const STATUS_URL = 'https://status.gearsnitch.com';

type Faq = {
  question: string;
  answer: React.ReactNode;
};

const faqs: Faq[] = [
  {
    question: 'How do I cancel my subscription?',
    answer: (
      <div className="space-y-2">
        <p>
          GearSnitch subscriptions purchased through the App Store are managed
          by Apple. Open{' '}
          <span className="text-zinc-200">
            Settings &rarr; Apple ID &rarr; Subscriptions
          </span>{' '}
          on your iPhone, tap GearSnitch, and choose Cancel Subscription. You
          keep access until the end of the current billing period.
        </p>
        <p>
          If you subscribed on the web (Stripe), open the Stripe Customer
          Portal from your{' '}
          <a
            href="/account"
            className="text-cyan-400 underline hover:text-cyan-300"
          >
            account page
          </a>{' '}
          and click Cancel plan.
        </p>
      </div>
    ),
  },
  {
    question: 'How do I pair a Bluetooth device?',
    answer: (
      <div className="space-y-2">
        <p>
          On iOS 26.3 and later GearSnitch supports one-tap pairing: open the
          Gear tab, tap the &quot;+&quot; in the top-right, and confirm the
          discovered device.
        </p>
        <p>
          On earlier iOS versions go to Gear &rarr; Add Device &rarr; Scan.
          Make sure Bluetooth is on and the gear is in pairing mode (refer to
          the gear&apos;s manual for the button combo). Tap the device when it
          appears in the list.
        </p>
      </div>
    ),
  },
  {
    question: 'How do I sync with Apple Health?',
    answer: (
      <p>
        Open GearSnitch &rarr; Account &rarr; Health Permissions and tap
        Connect Apple Health. iOS will present the HealthKit permission
        screen; toggle on every category you want to share (workouts, heart
        rate, ECG, medications, etc.) and tap Allow. You can change permissions
        at any time in iOS Settings &rarr; Privacy &amp; Security &rarr;
        Health &rarr; GearSnitch.
      </p>
    ),
  },
  {
    question: 'How do I delete my account?',
    answer: (
      <p>
        Open GearSnitch &rarr; Account &rarr; Delete Account, or visit{' '}
        <a
          href="/delete-account"
          className="text-cyan-400 underline hover:text-cyan-300"
        >
          gearsnitch.com/delete-account
        </a>
        . Deletion is permanent and removes your account, content, and backups
        within 90 days.
      </p>
    ),
  },
  {
    question: 'Why is my heart rate not showing?',
    answer: (
      <div className="space-y-2">
        <p>Walk through the troubleshooting list:</p>
        <ul className="list-inside list-disc space-y-1 pl-2">
          <li>
            Confirm GearSnitch has HealthKit read access to Heart Rate (iOS
            Settings &rarr; Health &rarr; Data Access &amp; Devices &rarr;
            GearSnitch).
          </li>
          <li>
            For Apple Watch: make sure the Watch is on your wrist and
            unlocked, and that Workout permissions are granted.
          </li>
          <li>
            For AirPods or Powerbeats Pro 2: place them in your ears, start a
            workout from the Apple Watch or in-ear gesture, and wait ~10
            seconds for the first sample.
          </li>
          <li>
            For external BLE chest straps: open the Gear tab, confirm the
            device shows Connected, and re-pair if it stays Disconnected.
          </li>
        </ul>
      </div>
    ),
  },
  {
    question: 'How do referrals work?',
    answer: (
      <p>
        Share your referral link or QR code (Account &rarr; Referrals). When
        someone signs up through it and starts a paid plan, you earn{' '}
        <span className="text-white">28 bonus days</span> on your active paid
        subscription (and they get their own welcome bonus). Share via
        Universal Link, the in-app QR sheet, or any messaging app. There is
        no cap on how many people you can refer.
      </p>
    ),
  },
  {
    question: 'Is GearSnitch a medical device?',
    answer: (
      <p className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3 text-amber-200">
        No. GearSnitch is not a medical device, is not diagnostic, and is not
        a substitute for professional medical advice, diagnosis, or treatment.
        Always talk to a licensed healthcare provider before starting,
        stopping, or changing a medication or regimen. In an emergency call
        your local emergency number.
      </p>
    ),
  },
  {
    question: 'What countries do you support?',
    answer: (
      <p>
        GearSnitch is available in the United States at launch. We are
        expanding to additional regions; follow{' '}
        <a
          href={STATUS_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="text-cyan-400 underline hover:text-cyan-300"
        >
          status.gearsnitch.com
        </a>{' '}
        for the latest availability list.
      </p>
    ),
  },
];

export default function SupportPage() {
  const [openFaq, setOpenFaq] = useState<number | null>(0);

  return (
    <div className="dark min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">
          Support
        </h1>
        <p className="mt-2 text-sm text-zinc-500">
          Help articles, contact options, and service status for GearSnitch.
        </p>

        <Separator className="my-8 bg-white/5" />

        <section className="grid gap-4 sm:grid-cols-3">
          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-base text-white">Email us</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm text-zinc-400">
              <p>Response time: 24&ndash;48 hours.</p>
              <a
                href={`mailto:${SUPPORT_EMAIL}`}
                className="block text-cyan-400 underline hover:text-cyan-300"
              >
                {SUPPORT_EMAIL}
              </a>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-base text-white">
                Report a bug
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm text-zinc-400">
              <p>Include device, OS, and steps to reproduce.</p>
              <a
                href={`mailto:${BUG_EMAIL}?subject=Bug%20report%3A%20%5Bshort%20description%5D`}
                className="block text-cyan-400 underline hover:text-cyan-300"
              >
                File a bug report
              </a>
            </CardContent>
          </Card>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-base text-white">
                Service status
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm text-zinc-400">
              <p>Live uptime, incidents, and maintenance.</p>
              <a
                href={STATUS_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="block text-cyan-400 underline hover:text-cyan-300"
              >
                {STATUS_URL.replace(/^https?:\/\//, '')}
              </a>
            </CardContent>
          </Card>
        </section>

        <Separator className="my-12 bg-white/5" />

        <section>
          <h2 className="mb-2 text-xl font-semibold text-white">
            Help articles
          </h2>
          <p className="mb-6 text-sm text-zinc-500">
            Quick answers to the questions we hear most often.
          </p>
          <div className="space-y-3">
            {faqs.map((faq, index) => {
              const isOpen = openFaq === index;
              return (
                <Card
                  key={faq.question}
                  className="cursor-pointer border-0 bg-zinc-900/60 ring-white/5 transition-colors hover:bg-zinc-900/80"
                  onClick={() => setOpenFaq(isOpen ? null : index)}
                >
                  <CardContent className="py-4">
                    <div className="flex items-start justify-between gap-4">
                      <p className="text-sm font-medium text-zinc-200">
                        {faq.question}
                      </p>
                      <svg
                        viewBox="0 0 24 24"
                        className={`mt-0.5 h-5 w-5 shrink-0 text-zinc-500 transition-transform ${
                          isOpen ? 'rotate-180' : ''
                        }`}
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        aria-hidden="true"
                      >
                        <path d="M19 9l-7 7-7-7" />
                      </svg>
                    </div>
                    {isOpen && (
                      <div className="mt-3 text-sm leading-relaxed text-zinc-400">
                        {faq.answer}
                      </div>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </section>

        <Separator className="my-12 bg-white/5" />

        <section>
          <h2 className="mb-2 text-xl font-semibold text-white">
            Still need help?
          </h2>
          <p className="text-sm leading-relaxed text-zinc-400">
            If your question is not covered above, email{' '}
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="text-cyan-400 underline hover:text-cyan-300"
            >
              {SUPPORT_EMAIL}
            </a>{' '}
            with your account email, the device you are using (model + iOS
            version), and as much detail as you can about what is happening.
            We answer every message.
          </p>
        </section>
      </main>

      <Footer />
    </div>
  );
}
