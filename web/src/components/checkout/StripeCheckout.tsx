import { useEffect, useMemo, useState } from 'react';
import { loadStripe, type PaymentRequest, type Stripe } from '@stripe/stripe-js';
import {
  CardElement,
  Elements,
  PaymentRequestButtonElement,
  useElements,
  useStripe,
} from '@stripe/react-stripe-js';
import { Button } from '@/components/ui/button';
import { api } from '@/lib/api';

const stripePublishableKey = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY ?? '';

let stripePromise: Promise<Stripe | null> | null = null;
function getStripe() {
  if (!stripePromise) {
    stripePromise = loadStripe(stripePublishableKey);
  }
  return stripePromise;
}

interface StripeCheckoutProps {
  cartId: string;
  amount: number;
  currency?: string;
  label?: string;
  onSuccess?: (orderId: string) => void;
  onError?: (message: string) => void;
  onCancel?: () => void;
}

interface ShippingAddressPayload {
  line1: string;
  line2?: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
}

function CheckoutForm({
  cartId,
  amount,
  currency = 'usd',
  label = 'GearSnitch Store',
  onSuccess,
  onError,
  onCancel,
}: StripeCheckoutProps) {
  const stripe = useStripe();
  const elements = useElements();

  const [fullName, setFullName] = useState('');
  const [addressLine1, setAddressLine1] = useState('');
  const [addressLine2, setAddressLine2] = useState('');
  const [city, setCity] = useState('');
  const [state, setState] = useState('');
  const [postalCode, setPostalCode] = useState('');
  const [paymentRequest, setPaymentRequest] = useState<PaymentRequest | null>(null);
  const [canUsePaymentRequest, setCanUsePaymentRequest] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [succeeded, setSucceeded] = useState(false);

  const shippingAddress = useMemo<ShippingAddressPayload>(
    () => ({
      line1: addressLine1.trim(),
      line2: addressLine2.trim() || undefined,
      city: city.trim(),
      state: state.trim(),
      postalCode: postalCode.trim(),
      country: 'US',
    }),
    [addressLine1, addressLine2, city, postalCode, state],
  );

  const isShippingValid =
    cartId.trim().length > 0
    && fullName.trim().length > 0
    && shippingAddress.line1.length > 0
    && shippingAddress.city.length > 0
    && shippingAddress.state.length > 0
    && shippingAddress.postalCode.length > 0;

  async function createPaymentIntent() {
    const res = await api.post<{
      clientSecret: string;
      paymentIntentId: string;
      amount: number;
      currency: string;
    }>('/store/payments/create-intent', {
      cartId,
      shippingAddress,
    });

    if (!res.success || !res.data) {
      throw new Error(res.error?.message ?? 'Could not create payment intent.');
    }

    return res.data;
  }

  async function finalizePayment(paymentIntentId: string) {
    const res = await api.post<{
      orderId: string;
      orderNumber: string;
      status: string;
      total: number;
      currency: string;
    }>('/store/payments/finalize', {
      paymentIntentId,
    });

    if (!res.success || !res.data) {
      throw new Error(res.error?.message ?? 'Could not finalize payment.');
    }

    return res.data.orderId;
  }

  useEffect(() => {
    if (!stripe) {
      return;
    }

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
      } else {
        setPaymentRequest(null);
        setCanUsePaymentRequest(false);
      }
    });

    pr.on('paymentmethod', async (ev) => {
      if (!isShippingValid) {
        ev.complete('fail');
        setErrorMsg('Complete your shipping details before using wallet checkout.');
        return;
      }

      setIsProcessing(true);
      setErrorMsg(null);

      try {
        const { clientSecret, paymentIntentId } = await createPaymentIntent();

        const { error: confirmError, paymentIntent } = await stripe.confirmCardPayment(
          clientSecret,
          { payment_method: ev.paymentMethod.id },
          { handleActions: false },
        );

        if (confirmError) {
          ev.complete('fail');
          setErrorMsg(confirmError.message ?? 'Payment failed.');
          onError?.(confirmError.message ?? 'Payment failed.');
          return;
        }

        ev.complete('success');

        if (paymentIntent?.status === 'requires_action') {
          const { error: actionError, paymentIntent: actionIntent } =
            await stripe.confirmCardPayment(clientSecret);

          if (actionError || actionIntent?.status !== 'succeeded') {
            const message = actionError?.message ?? 'Additional authentication failed.';
            setErrorMsg(message);
            onError?.(message);
            return;
          }
        }

        const orderId = await finalizePayment(paymentIntentId);
        setSucceeded(true);
        onSuccess?.(orderId);
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Something went wrong.';
        setErrorMsg(message);
        onError?.(message);
      } finally {
        setIsProcessing(false);
      }
    });
  }, [amount, cartId, currency, isShippingValid, label, onError, onSuccess, shippingAddress, stripe]);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!stripe || !elements) {
      return;
    }

    if (!isShippingValid) {
      setErrorMsg('Complete your shipping details before paying.');
      return;
    }

    const cardElement = elements.getElement(CardElement);
    if (!cardElement) {
      return;
    }

    setIsProcessing(true);
    setErrorMsg(null);

    try {
      const { clientSecret, paymentIntentId } = await createPaymentIntent();
      const { error, paymentIntent } = await stripe.confirmCardPayment(clientSecret, {
        payment_method: {
          card: cardElement,
          billing_details: {
            name: fullName.trim(),
          },
        },
      });

      if (error) {
        const message = error.message ?? 'Payment failed.';
        setErrorMsg(message);
        onError?.(message);
        return;
      }

      if (paymentIntent?.status !== 'succeeded') {
        const message = 'Payment did not complete successfully.';
        setErrorMsg(message);
        onError?.(message);
        return;
      }

      const orderId = await finalizePayment(paymentIntentId);
      setSucceeded(true);
      onSuccess?.(orderId);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Something went wrong.';
      setErrorMsg(message);
      onError?.(message);
    } finally {
      setIsProcessing(false);
    }
  }

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

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-5">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <label className="sm:col-span-2">
          <span className="mb-1 block text-xs uppercase tracking-wider text-zinc-500">Full name</span>
          <input
            value={fullName}
            onChange={(event) => setFullName(event.target.value)}
            className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-100 outline-none transition focus:border-emerald-500"
            placeholder="Jane Doe"
          />
        </label>

        <label className="sm:col-span-2">
          <span className="mb-1 block text-xs uppercase tracking-wider text-zinc-500">Address line 1</span>
          <input
            value={addressLine1}
            onChange={(event) => setAddressLine1(event.target.value)}
            className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-100 outline-none transition focus:border-emerald-500"
            placeholder="123 Gym Street"
          />
        </label>

        <label className="sm:col-span-2">
          <span className="mb-1 block text-xs uppercase tracking-wider text-zinc-500">Address line 2</span>
          <input
            value={addressLine2}
            onChange={(event) => setAddressLine2(event.target.value)}
            className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-100 outline-none transition focus:border-emerald-500"
            placeholder="Apartment, suite, etc. (optional)"
          />
        </label>

        <label>
          <span className="mb-1 block text-xs uppercase tracking-wider text-zinc-500">City</span>
          <input
            value={city}
            onChange={(event) => setCity(event.target.value)}
            className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-100 outline-none transition focus:border-emerald-500"
            placeholder="Austin"
          />
        </label>

        <label>
          <span className="mb-1 block text-xs uppercase tracking-wider text-zinc-500">State</span>
          <input
            value={state}
            onChange={(event) => setState(event.target.value)}
            className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-100 outline-none transition focus:border-emerald-500"
            placeholder="TX"
          />
        </label>

        <label className="sm:col-span-2">
          <span className="mb-1 block text-xs uppercase tracking-wider text-zinc-500">ZIP code</span>
          <input
            value={postalCode}
            onChange={(event) => setPostalCode(event.target.value)}
            className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-100 outline-none transition focus:border-emerald-500"
            placeholder="78701"
          />
        </label>
      </div>

      {canUsePaymentRequest && paymentRequest && isShippingValid ? (
        <>
          <PaymentRequestButtonElement
            options={{
              paymentRequest,
              style: {
                paymentRequestButton: {
                  type: 'default',
                  theme: 'dark',
                  height: '48px',
                },
              },
            }}
          />
          <div className="flex items-center gap-3 text-zinc-500">
            <span className="h-px flex-1 bg-zinc-700" />
            <span className="text-xs uppercase tracking-wider">or pay with card</span>
            <span className="h-px flex-1 bg-zinc-700" />
          </div>
        </>
      ) : canUsePaymentRequest ? (
        <p className="text-xs text-zinc-500">
          Complete your shipping details to enable Apple Pay or Google Pay.
        </p>
      ) : null}

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

      {errorMsg && <p className="text-sm text-red-400">{errorMsg}</p>}

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
          disabled={!stripe || isProcessing || !isShippingValid}
        >
          {isProcessing ? 'Processing...' : `Pay $${amount.toFixed(2)}`}
        </Button>
      </div>
    </form>
  );
}

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
