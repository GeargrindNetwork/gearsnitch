import { useState } from 'react';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';

const faqs = [
  {
    question: 'How do I connect my BLE fitness gear?',
    answer:
      'Open GearSnitch, go to the Gear tab, and tap "Scan for Devices." Make sure Bluetooth is enabled on your phone. The app will automatically discover nearby BLE-enabled fitness equipment. Tap a device to pair it.',
  },
  {
    question: 'How does gym detection work?',
    answer:
      'GearSnitch uses geo-fencing to detect when you arrive at a partnered gym. When you enter the geo-fenced zone, the app automatically activates session tracking and BLE monitoring. You must grant location permissions for this feature to work.',
  },
  {
    question: 'What happens when my gear disconnects?',
    answer:
      'When a tracked BLE device disconnects unexpectedly, GearSnitch triggers a panic alert with sound and haptic feedback. If you have emergency contacts configured, they will receive a push notification with your last known location.',
  },
  {
    question: 'How do I manage my subscription?',
    answer:
      'For App Store subscriptions, go to Settings > Apple ID > Subscriptions on your iPhone. For web subscriptions via Stripe, log into your account at gearsnitch.com/account and navigate to the Billing section.',
  },
  {
    question: 'How do I cancel my subscription?',
    answer:
      'App Store subscriptions can be cancelled through your iPhone Settings > Apple ID > Subscriptions. Web subscriptions can be cancelled from your account dashboard. You will retain access until the end of your current billing period.',
  },
  {
    question: 'Are peptide store products safe for consumption?',
    answer:
      'Products in the peptide store are sold for research purposes only and are not evaluated by the FDA. They are not intended to diagnose, treat, cure, or prevent any disease. You must be 21 or older to purchase. Consult a healthcare professional before use.',
  },
  {
    question: 'How do I delete my account?',
    answer:
      'Visit gearsnitch.com/delete-account or go to Account Settings in the app. You will have a 30-day grace period to reactivate before all data is permanently deleted.',
  },
  {
    question: 'Is my health data shared with anyone?',
    answer:
      'No. HealthKit data stays on your device and in Apple Health. It is never sold, shared with advertisers, or sent to third parties. We only read/write workout data with your explicit permission.',
  },
  {
    question: 'How does the referral program work?',
    answer:
      'Share your unique referral code or QR code with friends. When they subscribe, you earn 90 days of free premium access per referral. There is no cap on referral rewards.',
  },
  {
    question: 'What devices are compatible with GearSnitch?',
    answer:
      'GearSnitch requires iOS 16.0 or later. BLE monitoring works with any Bluetooth Low Energy device. HealthKit integration is available on iPhones with Apple Health.',
  },
];

export default function SupportPage() {
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    subject: '',
    message: '',
  });
  const [submitted, setSubmitted] = useState(false);
  const [openFaq, setOpenFaq] = useState<number | null>(null);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    // In production this would POST to the API
    setSubmitted(true);
  }

  function handleChange(
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>
  ) {
    setFormData((prev) => ({ ...prev, [e.target.name]: e.target.value }));
  }

  return (
    <div className="min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">Support</h1>
        <p className="mt-2 text-sm text-zinc-500">
          Have a question? Check the FAQ below or send us a message.
        </p>

        <Separator className="my-8 bg-white/5" />

        {/* FAQ Section */}
        <section>
          <h2 className="mb-6 text-xl font-semibold text-white">
            Frequently Asked Questions
          </h2>
          <div className="space-y-3">
            {faqs.map((faq, index) => (
              <Card
                key={index}
                className="cursor-pointer border-0 bg-zinc-900/60 ring-white/5 transition-colors hover:bg-zinc-900/80"
                onClick={() => setOpenFaq(openFaq === index ? null : index)}
              >
                <CardContent className="py-4">
                  <div className="flex items-start justify-between gap-4">
                    <p className="text-sm font-medium text-zinc-200">
                      {faq.question}
                    </p>
                    <svg
                      viewBox="0 0 24 24"
                      className={`mt-0.5 h-5 w-5 shrink-0 text-zinc-500 transition-transform ${
                        openFaq === index ? 'rotate-180' : ''
                      }`}
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                    >
                      <path d="M19 9l-7 7-7-7" />
                    </svg>
                  </div>
                  {openFaq === index && (
                    <p className="mt-3 text-sm leading-relaxed text-zinc-400">
                      {faq.answer}
                    </p>
                  )}
                </CardContent>
              </Card>
            ))}
          </div>
        </section>

        <Separator className="my-12 bg-white/5" />

        {/* Contact Form */}
        <section>
          <h2 className="mb-2 text-xl font-semibold text-white">Contact Us</h2>
          <p className="mb-6 text-sm text-zinc-500">
            Email:{' '}
            <a
              href="mailto:support@gearsnitch.com"
              className="text-cyan-400 underline hover:text-cyan-300"
            >
              support@gearsnitch.com
            </a>{' '}
            &middot; Response time: 24-48 hours
          </p>

          <Card className="border-0 bg-zinc-900/60 ring-white/5">
            <CardHeader>
              <CardTitle className="text-white">Send a Message</CardTitle>
            </CardHeader>
            <CardContent>
              {submitted ? (
                <div className="flex flex-col items-center gap-3 py-8 text-center">
                  <div className="flex h-12 w-12 items-center justify-center rounded-full bg-emerald-500/10">
                    <svg
                      viewBox="0 0 24 24"
                      className="h-6 w-6 text-emerald-400"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                    >
                      <path d="M20 6L9 17l-5-5" />
                    </svg>
                  </div>
                  <p className="text-base font-medium text-white">
                    Message sent successfully
                  </p>
                  <p className="text-sm text-zinc-400">
                    We'll get back to you within 24-48 hours.
                  </p>
                  <Button
                    variant="ghost"
                    className="mt-2 text-cyan-400 hover:text-cyan-300"
                    onClick={() => {
                      setSubmitted(false);
                      setFormData({ name: '', email: '', subject: '', message: '' });
                    }}
                  >
                    Send another message
                  </Button>
                </div>
              ) : (
                <form onSubmit={handleSubmit} className="space-y-5">
                  <div className="grid gap-5 sm:grid-cols-2">
                    <div className="space-y-2">
                      <Label htmlFor="name" className="text-zinc-300">
                        Name
                      </Label>
                      <Input
                        id="name"
                        name="name"
                        required
                        value={formData.name}
                        onChange={handleChange}
                        placeholder="Your name"
                        className="border-white/10 bg-zinc-800/50 text-white placeholder:text-zinc-600 focus:border-cyan-500/50 focus:ring-cyan-500/20"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="email" className="text-zinc-300">
                        Email
                      </Label>
                      <Input
                        id="email"
                        name="email"
                        type="email"
                        required
                        value={formData.email}
                        onChange={handleChange}
                        placeholder="you@example.com"
                        className="border-white/10 bg-zinc-800/50 text-white placeholder:text-zinc-600 focus:border-cyan-500/50 focus:ring-cyan-500/20"
                      />
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="subject" className="text-zinc-300">
                      Subject
                    </Label>
                    <Input
                      id="subject"
                      name="subject"
                      required
                      value={formData.subject}
                      onChange={handleChange}
                      placeholder="What can we help with?"
                      className="border-white/10 bg-zinc-800/50 text-white placeholder:text-zinc-600 focus:border-cyan-500/50 focus:ring-cyan-500/20"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="message" className="text-zinc-300">
                      Message
                    </Label>
                    <textarea
                      id="message"
                      name="message"
                      required
                      rows={5}
                      value={formData.message}
                      onChange={handleChange}
                      placeholder="Describe your issue or question..."
                      className="w-full rounded-md border border-white/10 bg-zinc-800/50 px-3 py-2 text-sm text-white placeholder:text-zinc-600 focus:border-cyan-500/50 focus:outline-none focus:ring-2 focus:ring-cyan-500/20"
                    />
                  </div>
                  <Button
                    type="submit"
                    className="w-full bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400 sm:w-auto"
                  >
                    Send Message
                  </Button>
                </form>
              )}
            </CardContent>
          </Card>
        </section>
      </main>

      <Footer />
    </div>
  );
}
