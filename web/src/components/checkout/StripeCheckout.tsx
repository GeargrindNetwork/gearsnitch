import { useState, useEffect } from 'react';
import { loadStripe, type Stripe, type PaymentRequest } from '@stripe/stripe-js';
import {
  Elements,
  CardElement,
  PaymentRequestButtonElement,
  useStripe,
  useElements,
} from '@stripe/react-stripe-js';
import { Button } from '@/components/ui/button';
import { api } from '@/lib/api';

// ---------------------------------------------------------------------------
// Stripe initialization
// ---------------------------------------------------------------------------

const stripePublishableKey = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY ?? '';

let stripePromise: Promise<Stripe | null> | null = null;
function getStripe() {
  if (!stripePromise) {
    stripePromise = loadStripe(stripePublishableKey);
  }
  return stripePromise;
}

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------

interface StripeCheckoutProps {
  /** Cart total in dollars (e.g. 49.99) */
  amount: number;
  /** ISO 4217 currency code */
  currency?: string;
  /** Descriptive label shown on Apple/Google Pay sheets */
  label?: string;
  /** Called after a successful payment */
  onSuccess?: (paymentIntentId: string) => void;
  /** Called on permanent failure */
  onError?: (message: string) => void;
  /** Called when the user dismisses the checkout */
  onCancel?: () => void;
}

// ---------------------------------------------------------------------------
// Inner checkout form (must be rendered inside <Elements>)
// ---------------------------------------------------------------------------

function CheckoutForm({
  amount,
  currency = 'usd',
  label = 'GearSnitch Store',
  onSuccess,
  onError,
  onCancel,
}: StripeCheckoutProps) {
  const stripe = useStripe();
  const elements = useElements();

  const [paymentRequest, setPaymentRequest] = useState<PaymentRequest | null>(null);
  const [canUsePaymentRequest, setCanUsePaymentRequest] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [succeeded, setSucceeded] = useState(false);

  // ---- Payment Request (Apple Pay / Google Pay) ----

  useEffect(() => {
    if (!stripe) return;

    const pr = stripe.paymentRequest({
      country: 'US',
      currency,
      total: { label, amount: Math.round(amount * 100) },
      requestPayerName: true,
      requestPayerEmail: true,
    });

    pr.canMakePayment().then((result) => {
      if (result) {
        setPaymentRequest(pr);
        setCanUsePaymentRequest(true);
      }
    });

    pr.on('paymentmethod', async (ev) => {
      setIsProcessing(true);
      setErrorMsg(null);

      try {
        const intentRes = await api.post<{ clientSecret: string; paymentIntentId: string }>(
          '/store/payments/create-intent',
          { amount, currency },
        );

        if (!intentRes.success || !intentRes.data) {
          ev.complete('fail');
          setErrorMsg(intentRes.error?.message ?? 'Could not create payment.');
          setIsProcessing(false);
          return;
        }

        const { clientSecret, paymentIntentId } = intentRes.data;

        const { error: confirmError, paymentIntent } = await stripe.confirmCardPayment(
          clientSecret,
          { payment_method: ev.paymentMethod.id },
          { handleActions: false },
        );

        if (confirmError) {
          ev.complete('fail');
          setErrorMsg(confirmError.message ?? 'Payment failed.');
        } else if (paymentIntent?.status === 'requires_action') {
          ev.complete('success');
          const { error: actionError } = await stripe.confirmCardPayment(clientSecret);
          if (actionError) {
            setErrorMsg(actionError.message ?? 'Authentication failed.');
          } else {
            setSucceeded(true);
            onSuccess?.(paymentIntentId);
          }
        } else {
          ev.complete('success');
          setSucceeded(true);
          onSuccess?.(paymentIntentId);
        }
      } catch {
        ev.complete('fail');
        setErrorMsg('Something went wrong. Please try again.');
      } finally {
        setIsProcessing(false);
      }
    });
  }, [stripe, amount, currency, label, onSuccess]);

  // ---- Manual Card Submit ----

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!stripe || !elements) return;

    const cardElement = elements.getElement(CardElement);
    if (!cardElement) return;

    setIsProcessing(true);
    setErrorMsg(null);

    try {
      const intentRes = await api.post<{ clientSecret: string; paymentIntentId: string }>(
        '/store/payments/create-intent',
        { amount, currency },
      );

      if (!intentRes.success || !intentRes.data) {
        setErrorMsg(intentRes.error?.message ?? 'Could not create payment.');
        setIsProcessing(false);
        return;
      }

      const { clientSecret, paymentIntentId } = intentRes.data;

      const { error, paymentIntent } = await stripe.confirmCardPayment(clientSecret, {
        payment_method: { card: cardElement },
      });

      if (error) {
        setErrorMsg(error.message ?? 'Payment failed.');
        onError?.(error.message ?? 'Payment failed.');
      } else if (paymentIntent?.status === 'succeeded') {
        setSucceeded(true);
        onSuccess?.(paymentIntentId);
      }
    } catch {
      setErrorMsg('Something went wrong. Please try again.');
    } finally {
      setIsProcessing(false);
    }
  }

  // ---- Success state ----

  if (succeeded) {
    return (
      <div className="flex flex-col items-center gap-4 py-8 text-center">
        <div className="flex h-14 w-14 items-center justify-center rounded-full bg-emerald-500/20">
          <svg className="h-7 w-7 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
          </svg>
        </div>
        <p className="text-lg font-semibold text-zinc-100">Payment Successful</p>
        <p className="text-sm text-zinc-400">Your order is being processed.</p>
      </div>
    );
  }

  // ---- Form ----

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-5">
      {/* Apple Pay / Google Pay button */}
      {canUsePaymentRequest && paymentRequest && (
        <>
          <PaymentRequestButtonElement
            options={{
              paymentRequest,
              style: {
                paymentRequestButton: { type: 'default', theme: 'dark', height: '48px' },
              },
            }}
          />
          <div className="flex items-center gap-3 text-zinc-500">
            <span className="h-px flex-1 bg-zinc-700" />
            <span className="text-xs uppercase tracking-wider">or pay with card</span>
            <span className="h-px flex-1 bg-zinc-700" />
          </div>
        </>
      )}

      {/* Card element */}
      <div className="rounded-lg border border-zinc-700 bg-zinc-900 px-4 py-3">
        <CardElement
          options={{
            style: {
              base: {
                fontSize: '16px',
                color: '#e4e4e7',
                '::placeholder': { color: '#71717a' },
                iconColor: '#10b981',
              },
              invalid: { color: '#ef4444', iconColor: '#ef4444' },
            },
          }}
        />
      </div>

      {/* Error */}
      {errorMsg && (
        <p className="text-sm text-red-400">{errorMsg}</p>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        {onCancel && (
          <Button
            type="button"
            variant="outline"
            className="flex-1 border-zinc-700 text-zinc-300 hover:bg-zinc-800"
            onClick={onCancel}
            disabled={isProcessing}
          >
            Cancel
          </Button>
        )}
        <Button
          type="submit"
          className="flex-1 bg-emerald-600 text-white hover:bg-emerald-500 disabled:opacity-50"
          disabled={!stripe || isProcessing}
        >
          {isProcessing ? 'Processing...' : `Pay $${amount.toFixed(2)}`}
        </Button>
      </div>
    </form>
  );
}

// ---------------------------------------------------------------------------
// Public wrapper — provides the Elements context
// ---------------------------------------------------------------------------

export default function StripeCheckout(props: StripeCheckoutProps) {
  return (
    <Elements
      stripe={getStripe()}
      options={{
        appearance: {
          theme: 'night',
          variables: {
            colorPrimary: '#10b981',
            colorBackground: '#18181b',
            colorText: '#e4e4e7',
            colorDanger: '#ef4444',
            borderRadius: '8px',
          },
        },
      }}
    >
      <CheckoutForm {...props} />
    </Elements>
  );
}
