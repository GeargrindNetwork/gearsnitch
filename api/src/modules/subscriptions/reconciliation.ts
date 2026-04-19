import { Subscription, type ISubscription } from '../../models/Subscription.js';
import { EventLog } from '../../models/EventLog.js';
import logger from '../../utils/logger.js';

/**
 * Weekly subscription state reconciliation.
 *
 * Webhooks (Apple Server Notifications v2, Stripe customer.subscription.*)
 * are the source-of-truth writers for `Subscription` rows. In practice,
 * webhooks can be dropped, arrive in the wrong order, or race against
 * other writes. This reconciler walks the non-terminal rows once a week,
 * asks each provider what its current state is, and heals any drift.
 *
 * This module is intentionally IO-plugged: the two provider clients are
 * injected (see `AppleReconcilerClient` / `StripeReconcilerClient`) so the
 * worker can bind them to the real Apple App Store Server API / Stripe
 * SDK, the admin route can run a one-shot reconciliation with the same
 * bindings, and tests can pass mocks.
 *
 * Out of scope (do NOT modify here):
 *   - Apple webhook handlers (`appleServerNotifications.ts`)
 *   - Stripe webhook handlers (`stripeSubscriptionWebhookService.ts`)
 *   - Apple JWS validation (`subscriptionService.ts:validateAppleTransaction`)
 */

export type ReconcilerStatus = ISubscription['status'];

/**
 * Statuses that are potentially-live and therefore candidates for
 * reconciliation. Terminal statuses (cancelled, expired, refunded, revoked)
 * are skipped — re-validating a row we've already written off wastes
 * provider quota and can only cause regressions.
 */
export const LIVE_RECONCILIATION_STATUSES: ReconcilerStatus[] = [
  'active',
  'grace_period',
  'past_due',
];

/** The shape the reconciler cares about — a subset of ISubscription. */
export interface ReconcilerSubscription {
  id: string;
  userId: string;
  provider: string;
  providerOriginalTransactionId: string;
  stripeSubscriptionId?: string | null;
  status: ReconcilerStatus;
  expiryDate: Date;
  autoRenew: boolean;
}

/** Normalised provider response. */
export interface ProviderState {
  status: ReconcilerStatus;
  expiryDate: Date;
  autoRenew: boolean;
}

export type ProviderLookupResult =
  | { outcome: 'found'; state: ProviderState }
  | { outcome: 'not_found' }
  | { outcome: 'transient_error'; error: string };

export interface AppleReconcilerClient {
  lookup(sub: ReconcilerSubscription): Promise<ProviderLookupResult>;
}

export interface StripeReconcilerClient {
  lookup(sub: ReconcilerSubscription): Promise<ProviderLookupResult>;
}

export interface ReconcilerClients {
  apple: AppleReconcilerClient;
  stripe: StripeReconcilerClient;
}

export type ReconcilerOutcome =
  | { kind: 'noop' }
  | { kind: 'drift_healed'; before: ProviderState; after: ProviderState }
  | { kind: 'not_at_provider' }
  | { kind: 'transient_error'; error: string }
  | { kind: 'unsupported_provider'; provider: string };

export interface ReconciliationCounters {
  rows_scanned: number;
  drift_healed: number;
  not_at_provider: number;
  failed: number;
  unsupported_provider: number;
}

export interface ReconciliationRunSummary {
  startedAt: Date;
  completedAt: Date;
  durationMs: number;
  counters: ReconciliationCounters;
}

/**
 * Pure drift-detection: compare the Mongo snapshot with the provider's
 * current state and decide what to do. No IO happens here — callers feed
 * in the lookup result and apply the resulting outcome.
 *
 * Rules:
 *   - `not_found` → caller marks Mongo row `expired`.
 *   - `transient_error` → caller leaves the row alone, logs, retries next week.
 *   - `found` with a material difference → caller heals Mongo to match.
 *
 * A "material difference" is any of status, expiryDate (to the millisecond),
 * or autoRenew. `lastValidatedAt` alone is not drift — it's always refreshed.
 */
export function decideReconciliationOutcome(
  sub: ReconcilerSubscription,
  lookup: ProviderLookupResult,
): ReconcilerOutcome {
  if (lookup.outcome === 'not_found') {
    return { kind: 'not_at_provider' };
  }
  if (lookup.outcome === 'transient_error') {
    return { kind: 'transient_error', error: lookup.error };
  }

  const providerState = lookup.state;
  const statusDiffers = providerState.status !== sub.status;
  const expiryDiffers =
    providerState.expiryDate.getTime() !== sub.expiryDate.getTime();
  const autoRenewDiffers = providerState.autoRenew !== sub.autoRenew;

  if (!statusDiffers && !expiryDiffers && !autoRenewDiffers) {
    return { kind: 'noop' };
  }

  return {
    kind: 'drift_healed',
    before: {
      status: sub.status,
      expiryDate: sub.expiryDate,
      autoRenew: sub.autoRenew,
    },
    after: providerState,
  };
}

/**
 * Select the right provider client for a row.
 */
function resolveClient(
  sub: ReconcilerSubscription,
  clients: ReconcilerClients,
): AppleReconcilerClient | StripeReconcilerClient | null {
  if (sub.provider === 'apple') return clients.apple;
  if (sub.provider === 'stripe') return clients.stripe;
  return null;
}

/**
 * Reconcile a single subscription row. This is the per-row orchestration
 * (IO + persistence); it calls `decideReconciliationOutcome` for the
 * pure decision.
 */
export async function reconcileOne(
  sub: ReconcilerSubscription,
  clients: ReconcilerClients,
): Promise<ReconcilerOutcome> {
  const client = resolveClient(sub, clients);
  if (!client) {
    return { kind: 'unsupported_provider', provider: sub.provider };
  }

  let lookup: ProviderLookupResult;
  try {
    lookup = await client.lookup(sub);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    lookup = { outcome: 'transient_error', error: message };
  }

  const outcome = decideReconciliationOutcome(sub, lookup);

  // Persist Mongo side-effects + emit EventLog rows.
  switch (outcome.kind) {
    case 'drift_healed': {
      await Subscription.updateOne(
        { _id: sub.id },
        {
          $set: {
            status: outcome.after.status,
            expiryDate: outcome.after.expiryDate,
            autoRenew: outcome.after.autoRenew,
            lastValidatedAt: new Date(),
          },
        },
      );
      await EventLog.create({
        userId: sub.userId,
        eventType: 'SubscriptionDriftHealed',
        source: 'system',
        metadata: {
          subscriptionId: sub.id,
          provider: sub.provider,
          before: {
            status: outcome.before.status,
            expiryDate: outcome.before.expiryDate.toISOString(),
            autoRenew: outcome.before.autoRenew,
          },
          after: {
            status: outcome.after.status,
            expiryDate: outcome.after.expiryDate.toISOString(),
            autoRenew: outcome.after.autoRenew,
          },
        },
      });
      logger.info('Reconciliation healed subscription drift', {
        subscriptionId: sub.id,
        provider: sub.provider,
        before: outcome.before.status,
        after: outcome.after.status,
      });
      break;
    }
    case 'not_at_provider': {
      await Subscription.updateOne(
        { _id: sub.id },
        {
          $set: {
            status: 'expired',
            lastValidatedAt: new Date(),
          },
        },
      );
      await EventLog.create({
        userId: sub.userId,
        eventType: 'SubscriptionNotAtProvider',
        source: 'system',
        metadata: {
          subscriptionId: sub.id,
          provider: sub.provider,
          providerOriginalTransactionId: sub.providerOriginalTransactionId,
          previousStatus: sub.status,
        },
      });
      logger.warn('Reconciliation could not find subscription at provider', {
        subscriptionId: sub.id,
        provider: sub.provider,
      });
      break;
    }
    case 'transient_error': {
      await EventLog.create({
        userId: sub.userId,
        eventType: 'ReconciliationFailed',
        source: 'system',
        metadata: {
          subscriptionId: sub.id,
          provider: sub.provider,
          error: outcome.error,
        },
      });
      logger.error('Reconciliation provider call failed transiently', {
        subscriptionId: sub.id,
        provider: sub.provider,
        error: outcome.error,
      });
      break;
    }
    case 'unsupported_provider': {
      logger.warn('Reconciliation skipped unsupported provider', {
        subscriptionId: sub.id,
        provider: outcome.provider,
      });
      break;
    }
    case 'noop':
      // Row is already in sync — still bump lastValidatedAt so ops can
      // see the row was checked this week.
      await Subscription.updateOne(
        { _id: sub.id },
        { $set: { lastValidatedAt: new Date() } },
      );
      break;
  }

  return outcome;
}

export interface ReconcileAllOptions {
  /** Cap per iteration to avoid long Mongo cursors in a single tick. Default 100. */
  batchSize?: number;
  /** Delay in ms between provider calls to avoid burst rate-limits. Default 10ms. */
  pacingMs?: number;
  /** Override for tests; defaults to the shared Subscription model. */
  subscriptionModel?: typeof Subscription;
}

function toReconcilerSubscription(doc: ISubscription): ReconcilerSubscription {
  return {
    id: String(doc._id),
    userId: String(doc.userId),
    provider: doc.provider,
    providerOriginalTransactionId: doc.providerOriginalTransactionId,
    stripeSubscriptionId: doc.stripeSubscriptionId ?? null,
    status: doc.status,
    expiryDate: doc.expiryDate,
    autoRenew: doc.autoRenew,
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Walk every non-terminal Subscription and reconcile it. Returns the
 * aggregated run summary; also persists a `ReconciliationRunComplete`
 * EventLog row that the admin `/last-run` endpoint reads.
 */
export async function reconcileAllSubscriptions(
  clients: ReconcilerClients,
  options: ReconcileAllOptions = {},
): Promise<ReconciliationRunSummary> {
  const { batchSize = 100, pacingMs = 10, subscriptionModel = Subscription } =
    options;

  const startedAt = new Date();
  const counters: ReconciliationCounters = {
    rows_scanned: 0,
    drift_healed: 0,
    not_at_provider: 0,
    failed: 0,
    unsupported_provider: 0,
  };

  const cursor = subscriptionModel
    .find({ status: { $in: LIVE_RECONCILIATION_STATUSES } })
    .batchSize(batchSize)
    .cursor();

  let batchPosition = 0;

  // `for await` + `cursor()` is the BullMQ-friendly streaming pattern.
  for await (const doc of cursor) {
    const sub = toReconcilerSubscription(doc as ISubscription);
    counters.rows_scanned += 1;

    const outcome = await reconcileOne(sub, clients);

    switch (outcome.kind) {
      case 'drift_healed':
        counters.drift_healed += 1;
        break;
      case 'not_at_provider':
        counters.not_at_provider += 1;
        break;
      case 'transient_error':
        counters.failed += 1;
        break;
      case 'unsupported_provider':
        counters.unsupported_provider += 1;
        break;
      case 'noop':
      default:
        break;
    }

    batchPosition += 1;
    if (pacingMs > 0 && batchPosition % 1 === 0) {
      // Pace every provider call (not just every batch) to smooth out
      // bursts against Stripe's per-second rate limit.
      await sleep(pacingMs);
    }

    if (batchPosition >= batchSize) {
      batchPosition = 0;
    }
  }

  const completedAt = new Date();
  const summary: ReconciliationRunSummary = {
    startedAt,
    completedAt,
    durationMs: completedAt.getTime() - startedAt.getTime(),
    counters,
  };

  await EventLog.create({
    eventType: 'ReconciliationRunComplete',
    source: 'system',
    metadata: {
      startedAt: startedAt.toISOString(),
      completedAt: completedAt.toISOString(),
      durationMs: summary.durationMs,
      counters,
    },
  });

  logger.info('Reconciliation run complete', {
    durationMs: summary.durationMs,
    ...counters,
  });

  return summary;
}

/**
 * Fetch the most recent `ReconciliationRunComplete` EventLog row, or
 * null if the cron has never run.
 */
export async function getLastReconciliationRun(): Promise<
  ReconciliationRunSummary | null
> {
  const row = await EventLog.findOne({
    eventType: 'ReconciliationRunComplete',
  })
    .sort({ timestamp: -1 })
    .lean();

  if (!row) return null;

  const metadata = (row.metadata ?? {}) as Record<string, unknown>;
  const counters = (metadata.counters ?? {}) as Partial<ReconciliationCounters>;

  return {
    startedAt: new Date(String(metadata.startedAt ?? row.timestamp)),
    completedAt: new Date(String(metadata.completedAt ?? row.timestamp)),
    durationMs: Number(metadata.durationMs ?? 0),
    counters: {
      rows_scanned: Number(counters.rows_scanned ?? 0),
      drift_healed: Number(counters.drift_healed ?? 0),
      not_at_provider: Number(counters.not_at_provider ?? 0),
      failed: Number(counters.failed ?? 0),
      unsupported_provider: Number(counters.unsupported_provider ?? 0),
    },
  };
}
