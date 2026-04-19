import type { Job } from 'bullmq'
import StripeLib from 'stripe'
import type { Stripe } from 'stripe/cjs/stripe.core.js'
import {
  AppStoreServerAPI,
  Environment,
  SubscriptionStatus as AppleSubStatus,
  decodeTransaction,
  decodeRenewalInfo,
  type LastTransactionsItem,
} from 'app-store-server-api'
import { ObjectId } from 'mongodb'
import { getCollection } from '../utils/jobRuntime'
import { logger } from '../utils/logger'

/**
 * Weekly subscription reconciliation job.
 *
 * Source-of-truth writers (Apple Server Notifications, Stripe webhooks)
 * can drop events. This pass walks every non-terminal Subscription, asks
 * the provider for current state, and heals drift.
 *
 * The core decision logic is mirrored from
 * `api/src/modules/subscriptions/reconciliation.ts` — kept in sync by
 * the accompanying unit tests in `api/tests/subscription-reconciliation.test.cjs`.
 */

type ReconcilerStatus =
  | 'active'
  | 'expired'
  | 'grace_period'
  | 'cancelled'
  | 'past_due'
  | 'refunded'
  | 'revoked'

const LIVE_STATUSES: ReconcilerStatus[] = ['active', 'grace_period', 'past_due']

interface SubscriptionRow {
  _id: ObjectId
  userId: ObjectId
  provider: string
  providerOriginalTransactionId: string
  stripeSubscriptionId?: string | null
  status: ReconcilerStatus
  expiryDate: Date
  autoRenew: boolean
}

interface ProviderState {
  status: ReconcilerStatus
  expiryDate: Date
  autoRenew: boolean
}

type ProviderLookupResult =
  | { outcome: 'found'; state: ProviderState }
  | { outcome: 'not_found' }
  | { outcome: 'transient_error'; error: string }

interface Counters {
  rows_scanned: number
  drift_healed: number
  not_at_provider: number
  failed: number
  unsupported_provider: number
}

// ---------------------------------------------------------------------------
// Provider adapters
// ---------------------------------------------------------------------------

function mapAppleStatus(
  appleStatus: number,
  autoRenew: boolean,
  expiryDate: Date,
): ReconcilerStatus {
  switch (appleStatus) {
    case AppleSubStatus.Active:
      return expiryDate.getTime() > Date.now() ? 'active' : 'expired'
    case AppleSubStatus.Expired:
      return 'expired'
    case AppleSubStatus.InBillingRetry:
      return 'past_due'
    case AppleSubStatus.InBillingGracePeriod:
      return 'grace_period'
    case AppleSubStatus.Revoked:
      return 'revoked'
    default:
      return autoRenew ? 'active' : 'expired'
  }
}

function mapStripeStatus(
  stripeStatus: Stripe.Subscription.Status,
  cancelAtPeriodEnd: boolean,
): ReconcilerStatus {
  switch (stripeStatus) {
    case 'active':
    case 'trialing':
      return 'active'
    case 'past_due':
    case 'unpaid':
      return 'past_due'
    case 'canceled':
    case 'incomplete_expired':
      return 'cancelled'
    case 'incomplete':
      return 'expired'
    case 'paused':
      return 'grace_period'
    default:
      return cancelAtPeriodEnd ? 'active' : 'expired'
  }
}

function buildAppleClient():
  | ((sub: SubscriptionRow) => Promise<ProviderLookupResult>)
  | null {
  const key = process.env.APPLE_ASSA_KEY ?? ''
  const keyId = process.env.APPLE_ASSA_KEY_ID ?? ''
  const issuerId = process.env.APPLE_ASSA_ISSUER_ID ?? ''
  const bundleId = process.env.APPLE_BUNDLE_ID ?? ''
  if (!key || !keyId || !issuerId || !bundleId) {
    return null
  }

  const envRaw = process.env.APPLE_STOREKIT_ENV
  const environment =
    envRaw === Environment.Sandbox
      ? Environment.Sandbox
      : Environment.Production
  const api = new AppStoreServerAPI(key, keyId, issuerId, bundleId, environment)

  return async (sub) => {
    try {
      const statuses = await api.getSubscriptionStatuses(
        sub.providerOriginalTransactionId,
      )
      const matchingGroup =
        (statuses.data ?? []).find((g) =>
          (g.lastTransactions ?? []).some(
            (tx: LastTransactionsItem) =>
              tx.originalTransactionId === sub.providerOriginalTransactionId,
          ),
        ) ?? statuses.data?.[0]

      const lastTx = (matchingGroup?.lastTransactions ?? [])[0]
      if (!lastTx) return { outcome: 'not_found' }

      const [transaction, renewal] = await Promise.all([
        lastTx.signedTransactionInfo
          ? decodeTransaction(lastTx.signedTransactionInfo).catch(() => null)
          : Promise.resolve(null),
        lastTx.signedRenewalInfo
          ? decodeRenewalInfo(lastTx.signedRenewalInfo).catch(() => null)
          : Promise.resolve(null),
      ])

      const expiryDate = new Date(transaction?.expiresDate ?? 0)
      const autoRenew = renewal?.autoRenewStatus === 1

      return {
        outcome: 'found',
        state: {
          status: mapAppleStatus(
            typeof lastTx.status === 'number' ? lastTx.status : 0,
            autoRenew,
            expiryDate,
          ),
          expiryDate,
          autoRenew,
        },
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      if (/404|4040010|no such|not found/i.test(message)) {
        return { outcome: 'not_found' }
      }
      return { outcome: 'transient_error', error: message }
    }
  }
}

function buildStripeClient():
  | ((sub: SubscriptionRow) => Promise<ProviderLookupResult>)
  | null {
  const secret = process.env.STRIPE_SECRET_KEY ?? ''
  if (!secret) return null

  const stripe = new StripeLib(secret) as unknown as Stripe

  return async (sub) => {
    const subscriptionId =
      sub.stripeSubscriptionId ?? sub.providerOriginalTransactionId
    if (!subscriptionId) return { outcome: 'not_found' }

    try {
      const stripeSub = (await stripe.subscriptions.retrieve(
        subscriptionId,
      )) as Stripe.Subscription & {
        current_period_end?: number
        cancel_at_period_end?: boolean
      }
      const expiryMs =
        (stripeSub.current_period_end ?? 0) * 1000 || Date.now()
      return {
        outcome: 'found',
        state: {
          status: mapStripeStatus(
            stripeSub.status,
            stripeSub.cancel_at_period_end ?? false,
          ),
          expiryDate: new Date(expiryMs),
          autoRenew: !(stripeSub.cancel_at_period_end ?? false),
        },
      }
    } catch (err) {
      const errObj = err as {
        code?: string
        statusCode?: number
        message?: string
      }
      const message = errObj.message ?? String(err)
      const isMissing =
        errObj.code === 'resource_missing' ||
        errObj.statusCode === 404 ||
        /No such subscription/i.test(message)
      if (isMissing) return { outcome: 'not_found' }
      return { outcome: 'transient_error', error: message }
    }
  }
}

// ---------------------------------------------------------------------------
// Pure decision logic (kept parallel with api/src/modules/subscriptions/reconciliation.ts)
// ---------------------------------------------------------------------------

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------

const BATCH_SIZE = 100
const PACING_MS = 10

export async function processSubscriptionReconciliation(
  job: Job,
): Promise<void> {
  const startedAt = new Date()
  const counters: Counters = {
    rows_scanned: 0,
    drift_healed: 0,
    not_at_provider: 0,
    failed: 0,
    unsupported_provider: 0,
  }

  const subscriptions = getCollection('subscriptions')
  const eventLogs = getCollection('eventlogs')

  const appleClient = buildAppleClient()
  const stripeClient = buildStripeClient()

  if (!appleClient) {
    logger.warn(
      'Apple reconciler missing APPLE_ASSA_* env — Apple rows will be recorded as transient failures',
    )
  }
  if (!stripeClient) {
    logger.warn(
      'Stripe reconciler missing STRIPE_SECRET_KEY — Stripe rows will be recorded as transient failures',
    )
  }

  const cursor = subscriptions
    .find({ status: { $in: LIVE_STATUSES } })
    .batchSize(BATCH_SIZE)

  try {
    for await (const doc of cursor) {
      const sub = doc as unknown as SubscriptionRow
      counters.rows_scanned += 1

      let lookup: ProviderLookupResult
      if (sub.provider === 'apple') {
        lookup = appleClient
          ? await appleClient(sub).catch((err): ProviderLookupResult => ({
              outcome: 'transient_error',
              error: err instanceof Error ? err.message : String(err),
            }))
          : { outcome: 'transient_error', error: 'apple_reconciler_unconfigured' }
      } else if (sub.provider === 'stripe') {
        lookup = stripeClient
          ? await stripeClient(sub).catch((err): ProviderLookupResult => ({
              outcome: 'transient_error',
              error: err instanceof Error ? err.message : String(err),
            }))
          : { outcome: 'transient_error', error: 'stripe_reconciler_unconfigured' }
      } else {
        counters.unsupported_provider += 1
        logger.warn('Reconciliation skipped unsupported provider', {
          subscriptionId: sub._id.toString(),
          provider: sub.provider,
        })
        if (PACING_MS > 0) await sleep(PACING_MS)
        continue
      }

      const now = new Date()
      if (lookup.outcome === 'not_found') {
        await subscriptions.updateOne(
          { _id: sub._id },
          { $set: { status: 'expired', lastValidatedAt: now, updatedAt: now } },
        )
        await eventLogs.insertOne({
          userId: sub.userId,
          eventType: 'SubscriptionNotAtProvider',
          source: 'system',
          timestamp: now,
          createdAt: now,
          metadata: {
            subscriptionId: sub._id.toString(),
            provider: sub.provider,
            providerOriginalTransactionId: sub.providerOriginalTransactionId,
            previousStatus: sub.status,
          },
        })
        counters.not_at_provider += 1
        logger.warn('Reconciliation marked row expired (not at provider)', {
          subscriptionId: sub._id.toString(),
          provider: sub.provider,
        })
      } else if (lookup.outcome === 'transient_error') {
        await eventLogs.insertOne({
          userId: sub.userId,
          eventType: 'ReconciliationFailed',
          source: 'system',
          timestamp: now,
          createdAt: now,
          metadata: {
            subscriptionId: sub._id.toString(),
            provider: sub.provider,
            error: lookup.error,
          },
        })
        counters.failed += 1
        logger.error('Reconciliation transient provider failure', {
          subscriptionId: sub._id.toString(),
          provider: sub.provider,
          error: lookup.error,
        })
      } else {
        const statusDiffers = lookup.state.status !== sub.status
        const expiryDiffers =
          lookup.state.expiryDate.getTime() !==
          new Date(sub.expiryDate).getTime()
        const autoRenewDiffers = lookup.state.autoRenew !== sub.autoRenew

        if (statusDiffers || expiryDiffers || autoRenewDiffers) {
          await subscriptions.updateOne(
            { _id: sub._id },
            {
              $set: {
                status: lookup.state.status,
                expiryDate: lookup.state.expiryDate,
                autoRenew: lookup.state.autoRenew,
                lastValidatedAt: now,
                updatedAt: now,
              },
            },
          )
          await eventLogs.insertOne({
            userId: sub.userId,
            eventType: 'SubscriptionDriftHealed',
            source: 'system',
            timestamp: now,
            createdAt: now,
            metadata: {
              subscriptionId: sub._id.toString(),
              provider: sub.provider,
              before: {
                status: sub.status,
                expiryDate: new Date(sub.expiryDate).toISOString(),
                autoRenew: sub.autoRenew,
              },
              after: {
                status: lookup.state.status,
                expiryDate: lookup.state.expiryDate.toISOString(),
                autoRenew: lookup.state.autoRenew,
              },
            },
          })
          counters.drift_healed += 1
          logger.info('Reconciliation healed drift', {
            subscriptionId: sub._id.toString(),
            provider: sub.provider,
            before: sub.status,
            after: lookup.state.status,
          })
        } else {
          await subscriptions.updateOne(
            { _id: sub._id },
            { $set: { lastValidatedAt: now, updatedAt: now } },
          )
        }
      }

      if (PACING_MS > 0) await sleep(PACING_MS)
    }
  } finally {
    await cursor.close().catch(() => undefined)
  }

  const completedAt = new Date()
  const durationMs = completedAt.getTime() - startedAt.getTime()

  await eventLogs.insertOne({
    eventType: 'ReconciliationRunComplete',
    source: 'system',
    timestamp: completedAt,
    createdAt: completedAt,
    metadata: {
      startedAt: startedAt.toISOString(),
      completedAt: completedAt.toISOString(),
      durationMs,
      counters,
    },
  })

  logger.info('Subscription reconciliation run complete', {
    jobId: job.id,
    durationMs,
    ...counters,
  })
}
