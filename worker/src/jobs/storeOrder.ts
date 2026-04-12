import type { Job } from 'bullmq'
import {
  enqueueJob,
  getCollection,
  hashDedupeKey,
  publishRuntimeEvent,
  recordFromUnknown,
  requireString,
  toObjectId,
  withIdempotency,
} from '../utils/jobRuntime'
import { logger } from '../utils/logger'

interface StoreOrderJobData {
  orderId: string
  userId: string
}

function resolveNextStatus(currentStatus: string): string {
  if (currentStatus === 'paid') {
    return 'fulfilled'
  }

  return currentStatus
}

export async function processStoreOrder(job: Job<StoreOrderJobData>): Promise<void> {
  const data = recordFromUnknown(job.data)
  const orderId = requireString(data, 'orderId')
  const userId = requireString(data, 'userId')

  await withIdempotency(
    'store-order-processing',
    hashDedupeKey([orderId, userId]),
    async () => {
      const orders = getCollection('storeorders')
      const order = await orders.findOne({
        _id: toObjectId(orderId),
        userId: toObjectId(userId),
      })

      if (!order) {
        logger.warn('Skipping store-order job for missing order', {
          jobId: job.id,
          orderId,
          userId,
        })
        return
      }

      if (order.status === 'pending') {
        logger.info('Store order is still pending payment confirmation', {
          jobId: job.id,
          orderId,
          userId,
        })
        return
      }

      const nextStatus = resolveNextStatus(order.status)
      const now = new Date()

      if (nextStatus !== order.status) {
        await orders.updateOne(
          { _id: order._id },
          {
            $set: {
              status: nextStatus,
              updatedAt: now,
            },
          },
        )
      }

      await publishRuntimeEvent('events:store-order', {
        userId,
        target: 'user',
        eventName: 'store:order:update',
        payload: {
          orderId,
          orderNumber: order.orderNumber,
          status: nextStatus,
          total: order.total,
          updatedAt: now.toISOString(),
        },
      })

      await enqueueJob(
        'push-notifications',
        {
          userId,
          type: 'store_order',
          title: `Order ${order.orderNumber} updated`,
          body:
            nextStatus === 'fulfilled'
              ? 'Your order is now ready for fulfillment.'
              : `Order status changed to ${nextStatus}.`,
          data: {
            orderId,
            status: nextStatus,
          },
          dedupeKey: `store-order:${orderId}:${nextStatus}`,
        },
        `push-store-order:${orderId}:${nextStatus}`,
      )

      logger.info('Store order job processed', {
        jobId: job.id,
        orderId,
        userId,
        status: nextStatus,
      })
    },
  )
}
