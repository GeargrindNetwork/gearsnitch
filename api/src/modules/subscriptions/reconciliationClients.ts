import StripeLib from 'stripe';
import type { Stripe } from 'stripe/cjs/stripe.core.js';
import {
  AppStoreServerAPI,
  Environment,
  decodeTransaction,
  decodeRenewalInfo,
  SubscriptionStatus as AppleSubStatus,
  type LastTransactionsItem,
} from 'app-store-server-api';
import config from '../../config/index.js';
import logger from '../../utils/logger.js';
import type {
  AppleReconcilerClient,
  ProviderLookupResult,
  ProviderState,
  ReconcilerClients,
  ReconcilerSubscription,
  ReconcilerStatus,
  StripeReconcilerClient,
} from './reconciliation.js';

/**
 * Production provider adapters. These are the thin wrappers that bind the
 * reconciler to the real Apple App Store Server API and Stripe SDK.
 * Unit tests use bespoke fakes and never import this module.
 */

// ---------------------------------------------------------------------------
// Apple
// ---------------------------------------------------------------------------

function mapAppleStatus(
  appleStatus: number,
  autoRenew: boolean,
  expiryDate: Date,
): ReconcilerStatus {
  // From https://developer.apple.com/documentation/appstoreserverapi/status:
  //   1 = Active, 2 = Expired, 3 = In Billing Retry Period (past_due),
  //   4 = In Grace Period, 5 = Revoked.
  switch (appleStatus) {
    case AppleSubStatus.Active:
      return expiryDate.getTime() > Date.now() ? 'active' : 'expired';
    case AppleSubStatus.Expired:
      return 'expired';
    case AppleSubStatus.InBillingRetry:
      return 'past_due';
    case AppleSubStatus.InBillingGracePeriod:
      return 'grace_period';
    case AppleSubStatus.Revoked:
      return 'revoked';
    default:
      return autoRenew ? 'active' : 'expired';
  }
}

/**
 * Build a production Apple App Store Server API client. Requires the full
 * key/issuer/bundle trio in env — if any are missing, returns a stub that
 * reports transient errors (so reconciliation can still run Stripe-only
 * without Apple credentials in dev).
 */
export function createAppleReconcilerClient(): AppleReconcilerClient {
  const key = process.env.APPLE_ASSA_KEY ?? '';
  const keyId = process.env.APPLE_ASSA_KEY_ID ?? '';
  const issuerId = process.env.APPLE_ASSA_ISSUER_ID ?? '';
  const bundleId = process.env.APPLE_BUNDLE_ID ?? '';
  const envRaw = process.env.APPLE_STOREKIT_ENV;
  const environment =
    envRaw === Environment.Sandbox
      ? Environment.Sandbox
      : Environment.Production;

  if (!key || !keyId || !issuerId || !bundleId) {
    logger.warn(
      'Apple reconciler client unavailable: missing APPLE_ASSA_* env vars — Apple rows will log transient_error',
    );
    return {
      async lookup(): Promise<ProviderLookupResult> {
        return {
          outcome: 'transient_error',
          error: 'apple_reconciler_unconfigured',
        };
      },
    };
  }

  const api = new AppStoreServerAPI(key, keyId, issuerId, bundleId, environment);

  return {
    async lookup(sub: ReconcilerSubscription): Promise<ProviderLookupResult> {
      try {
        const statuses = await api.getSubscriptionStatuses(
          sub.providerOriginalTransactionId,
        );
        // Find the group whose lastTransaction matches this originalTransactionId.
        const matchingGroup =
          (statuses.data ?? []).find((g) =>
            (g.lastTransactions ?? []).some(
              (tx: LastTransactionsItem) =>
                tx.originalTransactionId === sub.providerOriginalTransactionId,
            ),
          ) ?? statuses.data?.[0];

        const lastTx = (matchingGroup?.lastTransactions ?? [])[0];
        if (!lastTx) {
          return { outcome: 'not_found' };
        }

        const [transaction, renewal] = await Promise.all([
          lastTx.signedTransactionInfo
            ? decodeTransaction(lastTx.signedTransactionInfo).catch(() => null)
            : Promise.resolve(null),
          lastTx.signedRenewalInfo
            ? decodeRenewalInfo(lastTx.signedRenewalInfo).catch(() => null)
            : Promise.resolve(null),
        ]);

        const expiryMs = transaction?.expiresDate ?? 0;
        const expiryDate = new Date(expiryMs);
        const autoRenew = renewal?.autoRenewStatus === 1;
        const state: ProviderState = {
          status: mapAppleStatus(
            typeof lastTx.status === 'number' ? lastTx.status : 0,
            autoRenew,
            expiryDate,
          ),
          expiryDate,
          autoRenew,
        };

        return { outcome: 'found', state };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        // Apple returns a 4040010 errorCode or HTTP 404 for unknown
        // originalTransactionId. Map that to `not_found`; everything else
        // is treated as transient.
        if (/404|4040010|no such|not found/i.test(message)) {
          return { outcome: 'not_found' };
        }
        return { outcome: 'transient_error', error: message };
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Stripe
// ---------------------------------------------------------------------------

function mapStripeStatus(
  stripeStatus: Stripe.Subscription.Status,
  cancelAtPeriodEnd: boolean,
): ReconcilerStatus {
  switch (stripeStatus) {
    case 'active':
    case 'trialing':
      return 'active';
    case 'past_due':
    case 'unpaid':
      return 'past_due';
    case 'canceled':
    case 'incomplete_expired':
      return 'cancelled';
    case 'incomplete':
      return 'expired';
    case 'paused':
      return 'grace_period';
    default:
      return cancelAtPeriodEnd ? 'active' : 'expired';
  }
}

let _stripe: Stripe | null = null;
function getStripeClient(): Stripe {
  if (_stripe === null) {
    _stripe = new StripeLib(config.stripeSecretKey) as unknown as Stripe;
  }
  return _stripe;
}

export function createStripeReconcilerClient(): StripeReconcilerClient {
  if (!config.stripeSecretKey) {
    logger.warn(
      'Stripe reconciler client unavailable: STRIPE_SECRET_KEY is empty — Stripe rows will log transient_error',
    );
    return {
      async lookup(): Promise<ProviderLookupResult> {
        return {
          outcome: 'transient_error',
          error: 'stripe_reconciler_unconfigured',
        };
      },
    };
  }

  return {
    async lookup(sub: ReconcilerSubscription): Promise<ProviderLookupResult> {
      const subscriptionId =
        sub.stripeSubscriptionId ?? sub.providerOriginalTransactionId;
      if (!subscriptionId) {
        return { outcome: 'not_found' };
      }

      try {
        const stripeSub = (await getStripeClient().subscriptions.retrieve(
          subscriptionId,
        )) as Stripe.Subscription & {
          current_period_end?: number;
          cancel_at_period_end?: boolean;
        };
        const expiryMs =
          (stripeSub.current_period_end ?? 0) * 1000 ||
          Date.now();
        const state: ProviderState = {
          status: mapStripeStatus(
            stripeSub.status,
            stripeSub.cancel_at_period_end ?? false,
          ),
          expiryDate: new Date(expiryMs),
          autoRenew: !(stripeSub.cancel_at_period_end ?? false),
        };
        return { outcome: 'found', state };
      } catch (err) {
        const errObj = err as { code?: string; statusCode?: number; message?: string };
        const message = errObj.message ?? String(err);
        const isMissing =
          errObj.code === 'resource_missing' ||
          errObj.statusCode === 404 ||
          /No such subscription/i.test(message);
        if (isMissing) return { outcome: 'not_found' };
        return { outcome: 'transient_error', error: message };
      }
    },
  };
}

export function createDefaultReconcilerClients(): ReconcilerClients {
  return {
    apple: createAppleReconcilerClient(),
    stripe: createStripeReconcilerClient(),
  };
}
