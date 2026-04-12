import type { Job } from 'bullmq'
import {
  getCollection,
  hashDedupeKey,
  optionalRecord,
  optionalString,
  recordFromUnknown,
  requireString,
  toObjectId,
  withIdempotency,
} from '../utils/jobRuntime'
import { logger } from '../utils/logger'

interface PushNotificationJobData {
  userId: string
  type: string
  title: string
  body: string
  data?: Record<string, unknown>
  dedupeKey?: string
}

function shouldSuppressNotification(
  type: string,
  preferences: Record<string, unknown>,
): string | null {
  if (preferences.pushEnabled !== true) {
    return 'push_disabled'
  }

  if (type === 'panic_alarm' && preferences.panicAlertsEnabled === false) {
    return 'panic_alerts_disabled'
  }

  if (type === 'disconnect_warning' && preferences.disconnectAlertsEnabled === false) {
    return 'disconnect_alerts_disabled'
  }

  return null
}

export async function processPushNotification(
  job: Job<PushNotificationJobData>,
): Promise<void> {
  const data = recordFromUnknown(job.data)
  const userId = requireString(data, 'userId')
  const type = requireString(data, 'type')
  const title = requireString(data, 'title')
  const body = requireString(data, 'body')
  const metadata = optionalRecord(data, 'data') ?? {}
  const dedupeKey =
    optionalString(data, 'dedupeKey')
    ?? hashDedupeKey([userId, type, title, body, JSON.stringify(metadata)])

  await withIdempotency('push-notifications', dedupeKey, async () => {
    const userIdObject = toObjectId(userId)
    const users = getCollection('users')
    const notificationTokens = getCollection('notificationtokens')
    const notificationLogs = getCollection('notificationlogs')

    const user = await users.findOne(
      { _id: userIdObject },
      { projection: { preferences: 1 } },
    )

    if (!user) {
      logger.warn('Skipping push notification for missing user', {
        jobId: job.id,
        userId,
        type,
      })
      return
    }

    const preferences =
      typeof user.preferences === 'object' && user.preferences !== null
        ? (user.preferences as Record<string, unknown>)
        : {}

    const suppressionReason = shouldSuppressNotification(type, preferences)
    if (suppressionReason) {
      logger.info('Push notification suppressed by preferences', {
        jobId: job.id,
        userId,
        type,
        suppressionReason,
      })
      return
    }

    const tokens = await notificationTokens
      .find({ userId: userIdObject, active: true })
      .toArray()

    if (tokens.length === 0) {
      logger.warn('Skipping push notification because no active tokens exist', {
        jobId: job.id,
        userId,
        type,
      })
      return
    }

    const now = new Date()
    await notificationLogs.insertMany(
      tokens.map((token) => ({
        userId: userIdObject,
        tokenId: token._id,
        notificationType: type,
        sentAt: now,
        deliveredAt: null,
        openedAt: null,
        failureReason: null,
        createdAt: now,
        title,
        body,
        metadata,
      })),
    )

    await notificationTokens.updateMany(
      { _id: { $in: tokens.map((token) => token._id) } },
      {
        $set: {
          lastUsedAt: now,
          updatedAt: now,
        },
      },
    )

    logger.info('Push notification dispatch recorded', {
      jobId: job.id,
      userId,
      type,
      tokenCount: tokens.length,
    })
  })
}
