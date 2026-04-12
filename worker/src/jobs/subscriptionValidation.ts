import type { Job } from 'bullmq'
import {
  hashDedupeKey,
  getCollection,
  publishRuntimeEvent,
  recordFromUnknown,
  requireString,
  toObjectId,
  withIdempotency,
} from '../utils/jobRuntime'
import { logger } from '../utils/logger'

interface SubscriptionValidationJobData {
  userId: string
  receiptData: string
}

interface AppleTransactionPayload {
  originalTransactionId?: string
  transactionId?: string
  productId?: string
  purchaseDate?: number
  expiresDate?: number
}

function decodeJwtPayload(jwsRepresentation: string): AppleTransactionPayload {
  const parts = jwsRepresentation.split('.')
  if (parts.length !== 3) {
    throw new Error('Invalid JWS format')
  }

  const json = Buffer.from(parts[1], 'base64url').toString('utf8')
  return JSON.parse(json) as AppleTransactionPayload
}

function addDays(baseDate: Date, days: number): Date {
  return new Date(baseDate.getTime() + days * 24 * 60 * 60 * 1000)
}

export async function processSubscriptionValidation(
  job: Job<SubscriptionValidationJobData>,
): Promise<void> {
  const data = recordFromUnknown(job.data)
  const userId = requireString(data, 'userId')
  const receiptData = requireString(data, 'receiptData')

  await withIdempotency(
    'subscription-validation',
    hashDedupeKey([userId, receiptData]),
    async () => {
      const payload = decodeJwtPayload(receiptData)
      if (!payload.originalTransactionId || !payload.productId || !payload.purchaseDate) {
        throw new Error('Receipt payload is missing required transaction fields')
      }

      const subscriptions = getCollection('subscriptions')
      const now = new Date()
      const purchaseDate = new Date(payload.purchaseDate)
      const baseExpiry = payload.expiresDate
        ? new Date(payload.expiresDate)
        : addDays(purchaseDate, 365)

      const existing = await subscriptions.findOne({
        provider: 'apple',
        providerOriginalTransactionId: payload.originalTransactionId,
      })

      const nextStatus = baseExpiry > now ? 'active' : 'expired'
      let subscriptionId: string
      let expiryDate = baseExpiry

      if (existing) {
        const extensionDays =
          typeof existing.extensionDays === 'number' ? existing.extensionDays : 0
        expiryDate = addDays(baseExpiry, extensionDays)

        await subscriptions.updateOne(
          { _id: existing._id },
          {
            $set: {
              userId: toObjectId(userId),
              productId: payload.productId,
              purchaseDate,
              expiryDate,
              status: expiryDate > now ? 'active' : nextStatus,
              lastValidatedAt: now,
              updatedAt: now,
            },
          },
        )

        subscriptionId = existing._id.toString()
      } else {
        const result = await subscriptions.insertOne({
          userId: toObjectId(userId),
          provider: 'apple',
          providerOriginalTransactionId: payload.originalTransactionId,
          productId: payload.productId,
          status: nextStatus,
          purchaseDate,
          expiryDate,
          lastValidatedAt: now,
          extensionDays: 0,
          createdAt: now,
          updatedAt: now,
        })

        subscriptionId = result.insertedId.toString()
      }

      await publishRuntimeEvent('events:subscription', {
        userId,
        target: 'user',
        eventName: 'subscription:update',
        payload: {
          subscriptionId,
          status: expiryDate > now ? 'active' : nextStatus,
          tier: payload.productId,
          expiresAt: expiryDate.toISOString(),
        },
      })

      logger.info('Subscription validation completed', {
        jobId: job.id,
        userId,
        subscriptionId,
        productId: payload.productId,
        status: expiryDate > now ? 'active' : nextStatus,
      })
    },
  )
}
