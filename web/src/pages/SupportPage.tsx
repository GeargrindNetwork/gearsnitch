import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { useAuth } from '@/lib/auth';
import { api } from '@/lib/api';

const fallbackFaqs = [
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
      'GearSnitch subscriptions are currently managed through the App Store. Open Settings > Apple ID > Subscriptions on your iPhone, or use the Manage in App Store button from gearsnitch.com/account.',
  },
  {
    question: 'How do I cancel my subscription?',
    answer:
      'Cancel through your iPhone Settings > Apple ID > Subscriptions. You will retain access until the end of your current billing period.',
  },
  {
    question: 'How does the referral program work?',
    answer:
      'Share your unique referral code or QR code with friends. When they subscribe, you earn 90 days of free premium access per referral. There is no cap on referral rewards.',
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
    question: 'What devices are compatible with GearSnitch?',
    answer:
      'GearSnitch requires iOS 16.0 or later. BLE monitoring works with any Bluetooth Low Energy device. HealthKit integration is available on iPhones with Apple Health.',
  },
];

type SupportFaqItem = {
  question: string;
  answer: string;
};

type SupportTicket = {
  _id: string;
  name: string;
  email: string;
  subject: string;
  message: string;
  status: 'open' | 'resolved' | 'closed';
  source: 'web' | 'ios' | 'email';
  createdAt: string;
  updatedAt: string;
};

type SupportTicketSubmitResponse = {
  ticketId: string;
  status: SupportTicket['status'];
  ticket?: SupportTicket;
};

const supportTicketsQueryKey = ['support-tickets'] as const;

function formatTicketDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date);
}

function ticketStatusClassName(status: SupportTicket['status']) {
  switch (status) {
    case 'resolved':
      return 'border-emerald-700 text-emerald-400';
    case 'closed':
      return 'border-zinc-700 text-zinc-400';
    case 'open':
    default:
      return 'border-cyan-700 text-cyan-300';
  }
}

export default function SupportPage() {
  const { isAuthenticated, user } = useAuth();
  const queryClient = useQueryClient();
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    subject: '',
    message: '',
  });
  const [submitted, setSubmitted] = useState(false);
  const [submittedTicketId, setSubmittedTicketId] = useState<string | null>(null);
  const [openFaq, setOpenFaq] = useState<number | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const faqQuery = useQuery({
    queryKey: ['support-faq'],
    queryFn: async () => {
      const res = await api.get<SupportFaqItem[]>('/support/faq');
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Could not load support FAQ.');
      }
      return res.data;
    },
    initialData: fallbackFaqs,
    staleTime: 5 * 60 * 1000,
  });

  const ticketsQuery = useQuery({
    queryKey: supportTicketsQueryKey,
    enabled: isAuthenticated,
    queryFn: async () => {
      const res = await api.get<SupportTicket[]>('/support/tickets');
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Could not load your support tickets.');
      }
      return res.data;
    },
  });

  useEffect(() => {
    setFormData((prev) => ({
      ...prev,
      name: prev.name || user?.displayName || '',
      email: prev.email || user?.email || '',
    }));
  }, [user?.displayName, user?.email]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setIsSubmitting(true);
    setError(null);

    try {
      const res = await api.post<SupportTicketSubmitResponse>('/support/tickets', {
        ...formData,
        source: 'web',
      });

      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Could not send your message.');
      }

      if (res.data.ticket) {
        queryClient.setQueryData<SupportTicket[]>(
          supportTicketsQueryKey,
          (current) => [res.data!.ticket!, ...(current ?? []).filter((ticket) => ticket._id !== res.data!.ticket!._id)],
        );
      }

      setSubmittedTicketId(res.data.ticketId);
      setSubmitted(true);
      setFormData((prev) => ({
        ...prev,
        subject: '',
        message: '',
      }));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send your message.');
    } finally {
      setIsSubmitting(false);
    }
  }

  function handleChange(
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>
  ) {
    setFormData((prev) => ({ ...prev, [e.target.name]: e.target.value }));
  }

  const faqs = faqQuery.data ?? fallbackFaqs;
  const recentTickets = ticketsQuery.data ?? [];

  return (
    <div className="min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-4xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">Support</h1>
        <p className="mt-2 text-sm text-zinc-500">
          Get quick answers, send us a message, and track your latest GearSnitch support requests.
        </p>

        <Separator className="my-8 bg-white/5" />

        <section>
          <h2 className="mb-6 text-xl font-semibold text-white">
            Frequently Asked Questions
          </h2>
          <div className="space-y-3">
            {faqs.map((faq, index) => (
              <Card
                key={faq.question}
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

        <section>
          <div className="mb-4 flex items-center justify-between gap-3">
            <div>
              <h2 className="text-xl font-semibold text-white">Recent Tickets</h2>
              <p className="mt-1 text-sm text-zinc-500">
                {isAuthenticated
                  ? 'Signed-in requests stay attached to your GearSnitch account.'
                  : 'Sign in to view the ticket history attached to your account.'}
              </p>
            </div>
            {!isAuthenticated && (
              <Badge className="border-zinc-700 text-zinc-400">Guest</Badge>
            )}
          </div>

          {isAuthenticated ? (
            <Card className="border-0 bg-zinc-900/60 ring-white/5">
              <CardContent className="space-y-4 py-6">
                {ticketsQuery.isLoading && (
                  <p className="text-sm text-zinc-500">Loading your tickets...</p>
                )}
                {!ticketsQuery.isLoading && ticketsQuery.error && (
                  <p className="text-sm text-red-400">
                    {ticketsQuery.error instanceof Error
                      ? ticketsQuery.error.message
                      : 'Could not load your ticket history.'}
                  </p>
                )}
                {!ticketsQuery.isLoading && !ticketsQuery.error && recentTickets.length === 0 && (
                  <p className="text-sm text-zinc-400">
                    No support tickets yet. When you contact us from the website or iPhone app, they will appear here.
                  </p>
                )}
                {recentTickets.map((ticket) => (
                  <div
                    key={ticket._id}
                    className="rounded-2xl border border-white/5 bg-black/20 p-4"
                  >
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <p className="font-medium text-white">{ticket.subject}</p>
                        <p className="mt-1 text-xs uppercase tracking-[0.18em] text-zinc-500">
                          Ticket {ticket._id.slice(-8).toUpperCase()}
                        </p>
                      </div>
                      <Badge className={ticketStatusClassName(ticket.status)}>
                        {ticket.status}
                      </Badge>
                    </div>
                    <p className="mt-3 text-sm leading-relaxed text-zinc-400">
                      {ticket.message}
                    </p>
                    <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-zinc-500">
                      <span>Created {formatTicketDate(ticket.createdAt)}</span>
                      <span>Source: {ticket.source}</span>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          ) : (
            <Card className="border-0 bg-zinc-900/60 ring-white/5">
              <CardContent className="py-6 text-sm text-zinc-400">
                The support form works without an account, but only signed-in users can review prior tickets in the web dashboard.
              </CardContent>
            </Card>
          )}
        </section>

        <Separator className="my-12 bg-white/5" />

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
                    We&apos;ll get back to you within 24-48 hours.
                    {submittedTicketId ? ` Reference: ${submittedTicketId.slice(-8).toUpperCase()}.` : ''}
                  </p>
                  <Button
                    variant="ghost"
                    className="mt-2 text-cyan-400 hover:text-cyan-300"
                    onClick={() => {
                      setSubmitted(false);
                      setSubmittedTicketId(null);
                      setError(null);
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
                  {error && (
                    <p className="text-sm text-red-400">{error}</p>
                  )}
                  <Button
                    type="submit"
                    disabled={isSubmitting}
                    className="w-full bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400 sm:w-auto"
                  >
                    {isSubmitting ? 'Sending...' : 'Send Message'}
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
