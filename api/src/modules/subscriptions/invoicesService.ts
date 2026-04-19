import StripeLib from 'stripe';
import type { Stripe } from 'stripe/cjs/stripe.core.js';
import config from '../../config/index.js';
import { User } from '../../models/User.js';

/**
 * Stripe Invoices listing — read-only surface used by
 * `GET /api/v1/subscriptions/invoices` to render the Billing history page
 * (backlog item #22).
 *
 * Kept in its own module so we don't extend the write-heavy PaymentService
 * surface and so the route file does not own a raw Stripe client (the
 * existing portal-session contract test explicitly forbids `new StripeLib`
 * inside `routes.ts`). Lazy-init mirrors the pattern in PaymentService —
 * no Stripe SDK is constructed until first use, keeping type-check / CI
 * lanes that don't set STRIPE_SECRET_KEY happy.
 */

let _invoicesStripe: Stripe | null = null;
function invoicesStripeClient(): Stripe {
  if (_invoicesStripe === null) {
    _invoicesStripe = new StripeLib(config.stripeSecretKey) as unknown as Stripe;
  }
  return _invoicesStripe;
}

// Test / DI seam: lets unit tests inject a stubbed client without having to
// monkey-patch the `stripe` module's require cache. Production callers should
// never use this.
export function __setInvoicesStripeClientForTesting(client: Stripe | null): void {
  _invoicesStripe = client;
}

export interface SanitizedInvoice {
  id: string;
  number: string | null;
  createdAt: string;
  paidAt: string | null;
  amountPaid: number;
  amountDue: number;
  currency: string;
  status: 'paid' | 'open' | 'void' | 'uncollectible' | 'draft';
  hostedInvoiceUrl: string | null;
  invoicePdfUrl: string | null;
  description: string | null;
  periodStart: string | null;
  periodEnd: string | null;
}

export interface InvoiceListResult {
  invoices: SanitizedInvoice[];
  hasMore: boolean;
  nextCursor: string | null;
}

export class InvoiceListError extends Error {
  code: string;
  statusCode: number;

  constructor(message: string, code: string, statusCode = 502) {
    super(message);
    this.name = 'InvoiceListError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

function toIsoSeconds(epochSeconds: number | null | undefined): string | null {
  if (typeof epochSeconds !== 'number' || !Number.isFinite(epochSeconds) || epochSeconds <= 0) {
    return null;
  }
  return new Date(epochSeconds * 1000).toISOString();
}

function coerceStatus(
  raw: Stripe.Invoice['status'] | undefined,
): SanitizedInvoice['status'] {
  switch (raw) {
    case 'paid':
    case 'open':
    case 'void':
    case 'uncollectible':
    case 'draft':
      return raw;
    default:
      // Stripe's type union is wider than our API surface; anything unknown
      // (or null) is presented as "open" for display purposes. The real
      // source of truth is Stripe — the web UI only uses this for a badge.
      return 'open';
  }
}

export function sanitizeInvoice(raw: Stripe.Invoice): SanitizedInvoice {
  const created = toIsoSeconds(raw.created);

  return {
    id: raw.id,
    number: raw.number ?? null,
    createdAt: created ?? new Date(0).toISOString(),
    paidAt: toIsoSeconds(raw.status_transitions?.paid_at ?? null),
    amountPaid: typeof raw.amount_paid === 'number' ? raw.amount_paid : 0,
    amountDue: typeof raw.amount_due === 'number' ? raw.amount_due : 0,
    currency: typeof raw.currency === 'string' ? raw.currency : 'usd',
    status: coerceStatus(raw.status ?? undefined),
    hostedInvoiceUrl: raw.hosted_invoice_url ?? null,
    invoicePdfUrl: raw.invoice_pdf ?? null,
    description: raw.description ?? null,
    periodStart: toIsoSeconds(raw.period_start),
    periodEnd: toIsoSeconds(raw.period_end),
  };
}

/**
 * Fetch a sanitized page of invoices for the given user.
 *
 *   - If the user does not have a `stripeCustomerId` we return an empty
 *     list rather than 4xx — Apple-only subscribers legitimately have no
 *     Stripe invoices and the web UI should render the empty state.
 *   - Callers may forward an opaque `startingAfter` cursor from a previous
 *     response to paginate further into history.
 *   - Stripe SDK errors surface as `InvoiceListError` so the route layer
 *     can translate them into a 502 Bad Gateway.
 */
export async function listSanitizedInvoicesForUser(params: {
  userId: string;
  limit?: number;
  startingAfter?: string | null;
}): Promise<InvoiceListResult> {
  const { userId } = params;
  const limit = Math.min(Math.max(params.limit ?? 50, 1), 100);
  const startingAfter =
    typeof params.startingAfter === 'string' && params.startingAfter.trim().length > 0
      ? params.startingAfter
      : null;

  const user = await User.findById(userId);
  if (!user) {
    throw new InvoiceListError('User not found', 'USER_NOT_FOUND', 404);
  }

  if (!user.stripeCustomerId) {
    // Apple-only subscribers, or users who have never subscribed via Stripe,
    // get an empty list — not an error. The UI renders the empty state
    // explaining that iOS subscriptions are billed via Apple.
    return { invoices: [], hasMore: false, nextCursor: null };
  }

  const stripe = invoicesStripeClient();

  let page: Stripe.ApiList<Stripe.Invoice>;
  try {
    page = await stripe.invoices.list({
      customer: user.stripeCustomerId,
      limit,
      ...(startingAfter ? { starting_after: startingAfter } : {}),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Stripe invoice list failed';
    throw new InvoiceListError(
      `Failed to fetch invoices from Stripe: ${message}`,
      'STRIPE_INVOICE_LIST_FAILED',
      502,
    );
  }

  const invoices = (page.data ?? []).map(sanitizeInvoice);
  const nextCursor =
    page.has_more && invoices.length > 0 ? invoices[invoices.length - 1].id : null;

  return {
    invoices,
    hasMore: Boolean(page.has_more),
    nextCursor,
  };
}
