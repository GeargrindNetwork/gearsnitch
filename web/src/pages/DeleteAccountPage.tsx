import { useState } from 'react';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';

export default function DeleteAccountPage() {
  const { user, isAuthenticated, signOut } = useAuth();
  const [email, setEmail] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [submittedEmail, setSubmittedEmail] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fallbackEmail = isAuthenticated ? user?.email?.trim() ?? '' : '';
  const enteredEmail = email.trim().length > 0 ? email.trim() : fallbackEmail;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!confirmed || !isAuthenticated) return;

    if (!enteredEmail) {
      setError('Enter the email on your signed-in GearSnitch account to continue.');
      return;
    }

    if (user?.email && enteredEmail.toLowerCase() !== user.email.toLowerCase()) {
      setError('Enter the email on your signed-in GearSnitch account to continue.');
      return;
    }

    setIsSubmitting(true);
    setError(null);

    const res = await api.delete<{
      deletionRequestedAt: string;
      deletionScheduledFor: string;
      gracePeriodDays: number;
    }>('/users/me');

    if (!res.success) {
      setError(res.error?.message ?? 'Could not request account deletion.');
      setIsSubmitting(false);
      return;
    }

    setSubmittedEmail(enteredEmail);
    setSubmitted(true);
    setIsSubmitting(false);

    await signOut();
  }

  return (
    <div className="dark min-h-screen bg-black text-zinc-300">
      <Header />

      <main className="mx-auto max-w-2xl px-4 pb-20 pt-28 sm:px-6 lg:px-8">
        <h1 className="text-3xl font-bold tracking-tight text-white">Delete Account</h1>
        <p className="mt-2 text-sm text-zinc-500">
          Permanently delete your GearSnitch account and all associated data.
        </p>

        <Separator className="my-8 bg-white/5" />

        {/* What gets deleted */}
        <Card className="mb-8 border-0 bg-zinc-900/60 ring-white/5">
          <CardHeader>
            <CardTitle className="text-white">What Gets Deleted</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm leading-relaxed text-zinc-400">
            <p>
              When you delete your account, the following data will be permanently removed
              from our servers:
            </p>
            <ul className="list-inside list-disc space-y-2 pl-2">
              <li>Your profile information (name, email, profile picture)</li>
              <li>All tracked BLE devices and gear configurations</li>
              <li>Workout session history and fitness data</li>
              <li>Subscription and purchase history</li>
              <li>Referral data and earned rewards</li>
              <li>Emergency contacts and panic alert settings</li>
              <li>All app preferences and notification settings</li>
            </ul>

            <div className="mt-4 rounded-lg border border-amber-500/20 bg-amber-500/5 p-4">
              <div className="flex gap-3">
                <svg
                  viewBox="0 0 24 24"
                  className="mt-0.5 h-5 w-5 shrink-0 text-amber-400"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                >
                  <path d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
                </svg>
                <div>
                  <p className="font-medium text-amber-300">Important Notes</p>
                  <ul className="mt-2 list-inside list-disc space-y-1 text-amber-400/80">
                    <li>
                      HealthKit data in Apple Health is not affected and remains on your
                      device.
                    </li>
                    <li>
                      Active App Store subscriptions must be cancelled separately through
                      your iPhone Settings &gt; Apple ID &gt; Subscriptions.
                    </li>
                    <li>
                      This action cannot be undone after the 30-day grace period.
                    </li>
                  </ul>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* 30-day grace period */}
        <Card className="mb-8 border-0 bg-zinc-900/60 ring-white/5">
          <CardHeader>
            <CardTitle className="text-white">30-Day Grace Period</CardTitle>
          </CardHeader>
          <CardContent className="text-sm leading-relaxed text-zinc-400">
            <p>
              After you request deletion, your account will be deactivated immediately but
              your data will be retained for 30 days. During this grace period, you can
              sign back in to reactivate your account and restore all your data.
            </p>
            <p className="mt-3">
              After 30 days, all data is permanently and irreversibly deleted from our
              servers. No recovery is possible after this point.
            </p>
          </CardContent>
        </Card>

        {/* Deletion form */}
        <Card className="border-0 bg-zinc-900/60 ring-white/5">
          <CardHeader>
            <CardTitle className="text-white">Delete My Account</CardTitle>
          </CardHeader>
          <CardContent>
            {submitted ? (
              <div className="flex flex-col items-center gap-3 py-8 text-center">
                <div className="flex h-12 w-12 items-center justify-center rounded-full bg-red-500/10">
                  <svg
                    viewBox="0 0 24 24"
                    className="h-6 w-6 text-red-400"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                  >
                    <path d="M20 6L9 17l-5-5" />
                  </svg>
                </div>
                <p className="text-base font-medium text-white">
                  Account deletion requested
                </p>
                <p className="max-w-sm text-sm text-zinc-400">
                  Your account has been deactivated. You have 30 days to sign back in and
                  reactivate. After 30 days, all data will be permanently deleted.
                </p>
                <p className="mt-2 text-xs text-zinc-600">
                  A confirmation email has been sent to {submittedEmail}.
                </p>
              </div>
            ) : (
              <form onSubmit={handleSubmit} className="space-y-5">
                {!isAuthenticated && (
                  <div className="rounded-lg border border-amber-500/20 bg-amber-500/5 p-4 text-sm text-amber-200">
                    Sign in to the GearSnitch account you want to delete, then confirm your email below.
                  </div>
                )}

                <p className="text-sm text-zinc-400">
                  To confirm account deletion, enter the email address associated with your
                  GearSnitch account.
                </p>

                <div className="space-y-2">
                  <Label htmlFor="email" className="text-zinc-300">
                    Email Address
                  </Label>
                  <Input
                    id="email"
                    type="email"
                    required
                    value={enteredEmail}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="you@example.com"
                    className="border-white/10 bg-zinc-800/50 text-white placeholder:text-zinc-600 focus:border-cyan-500/50 focus:ring-cyan-500/20"
                  />
                </div>

                <label className="flex cursor-pointer items-start gap-3">
                  <input
                    type="checkbox"
                    checked={confirmed}
                    onChange={(e) => setConfirmed(e.target.checked)}
                    className="mt-1 h-4 w-4 rounded border-white/20 bg-zinc-800 text-red-500 focus:ring-red-500/20"
                  />
                  <span className="text-sm text-zinc-400">
                    I understand that after the 30-day grace period, my account and all
                    associated data will be permanently deleted and cannot be recovered.
                  </span>
                </label>

                {error && (
                  <p className="text-sm text-red-400">{error}</p>
                )}

                <Button
                  type="submit"
                  disabled={!confirmed || !enteredEmail || !isAuthenticated || isSubmitting}
                  className="w-full bg-red-600 font-semibold text-white hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
                >
                  {isSubmitting ? 'Submitting...' : 'Delete My Account'}
                </Button>
              </form>
            )}
          </CardContent>
        </Card>

        {/* Alternative */}
        <div className="mt-8 text-center text-sm text-zinc-600">
          <p>
            Need help instead?{' '}
            <a href="/support" className="text-cyan-400 underline hover:text-cyan-300">
              Contact support
            </a>{' '}
            or email{' '}
            <a
              href="mailto:support@gearsnitch.com"
              className="text-cyan-400 underline hover:text-cyan-300"
            >
              support@gearsnitch.com
            </a>
          </p>
        </div>
      </main>

      <Footer />
    </div>
  );
}
