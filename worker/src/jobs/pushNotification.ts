import type { Job } from 'bullmq'
import type { ObjectId } from 'mongodb'
import {
  APNS_REASON_BAD_DEVICE_TOKEN,
  APNS_REASON_NOT_CONFIGURED,
  APNS_REASON_UNREGISTERED,
  sendAPNsPush,
  setApnsLogger,
  type ApnsEnvironment,
  type ApnsPayload,
  type ApnsPushType,
  type ApnsSendResult,
} from '../utils/apnsClient'
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

// Wire winston into the APNs client so its warnings land in the same
// structured log stream as everything else the worker emits.
setApnsLogger({
  warn: (msg, meta) => logger.warn(msg, meta),
  error: (msg, meta) => logger.error(msg, meta),
  info: (msg, meta) => logger.info(msg, meta),
})

interface PushNotificationJobData {
  userId: string
  type: string
  title: string
  body: string
  data?: Record<string, unknown>
  dedupeKey?: string
}

interface NotificationTokenDoc {
  _id: ObjectId
  userId: ObjectId
  platform?: string
  token: string
  environment?: ApnsEnvironment
  active?: boolean
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

function buildApnsPayload(
  title: string,
  body: string,
  metadata: Record<string, unknown>,
  type: string,
): ApnsPayload {
  // Panic alarms map to time-sensitive / critical interruption so they
  // break through Focus modes. Other notifications are standard alerts.
  const interruptionLevel =
    type === 'panic_alarm' ? 'time-sensitive' : undefined

  const payload: ApnsPayload = {
    aps: {
      alert: { title, body },
      sound: 'default',
      ...(interruptionLevel ? { 'interruption-level': interruptionLevel } : {}),
    },
    type,
    ...metadata,
  }

  return payload
}

function pushTypeFor(type: string): ApnsPushType {
  // Anything that shows UI is `alert`. Silent/content-available jobs
  // should be enqueued with their own type — we default to `alert` here
  // because every current caller wants visible notifications.
  void type
  return 'alert'
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

    const tokens = (await notificationTokens
      .find({ userId: userIdObject, active: true })
      .toArray()) as unknown as NotificationTokenDoc[]

    if (tokens.length === 0) {
      logger.warn('Skipping push notification because no active tokens exist', {
        jobId: job.id,
        userId,
        type,
      })
      return
    }

    const apnsPayload = buildApnsPayload(title, body, metadata, type)
    const apnsPushType = pushTypeFor(type)
    const now = new Date()

    const logRows: Array<Record<string, unknown>> = []
    const deadTokenIds: ObjectId[] = []
    const deliveredTokenIds: ObjectId[] = []

    for (const token of tokens) {
      // Only iOS/watchOS tokens flow through APNs. Anything else (none
      // today, but future-proofed) is logged and skipped.
      if (token.platform && token.platform !== 'ios' && token.platform !== 'watchos') {
        logRows.push({
          userId: userIdObject,
          tokenId: token._id,
          notificationType: type,
          sentAt: now,
          deliveredAt: null,
          openedAt: null,
          failureReason: `UnsupportedPlatform:${token.platform}`,
          createdAt: now,
          title,
          body,
          metadata,
        })
        continue
      }

      const environment: ApnsEnvironment = token.environment ?? 'production'
      let result: ApnsSendResult
      try {
        result = await sendAPNsPush({
          deviceToken: token.token,
          payload: apnsPayload,
          environment,
          pushType: apnsPushType,
        })
      } catch (error) {
        // sendAPNsPush is meant to never throw — but belt-and-braces.
        logger.error('Unexpected APNs send exception', {
          jobId: job.id,
          userId,
          error: error instanceof Error ? error.message : String(error),
        })
        result = {
          success: false,
          statusCode: 0,
          reason: 'UnexpectedError',
        }
      }

      const failureReason = result.success ? null : result.reason ?? `HTTP_${result.statusCode}`

      logRows.push({
        userId: userIdObject,
        tokenId: token._id,
        notificationType: type,
        sentAt: now,
        deliveredAt: result.success ? now : null,
        openedAt: null,
        failureReason,
        createdAt: now,
        title,
        body,
        metadata: {
          ...metadata,
          ...(result.apnsId ? { apnsId: result.apnsId } : {}),
          ...(result.statusCode ? { apnsStatusCode: result.statusCode } : {}),
        },
      })

      if (
        result.reason === APNS_REASON_BAD_DEVICE_TOKEN
        || result.reason === APNS_REASON_UNREGISTERED
      ) {
        deadTokenIds.push(token._id)
      } else if (result.success) {
        deliveredTokenIds.push(token._id)
      } else if (result.reason === APNS_REASON_NOT_CONFIGURED) {
        // Swallow — we already logged a structured warn inside the client.
      } else {
        logger.warn('APNs rejected push', {
          jobId: job.id,
          userId,
          type,
          statusCode: result.statusCode,
          reason: result.reason,
        })
      }
    }

    if (logRows.length > 0) {
      await notificationLogs.insertMany(logRows)
    }

    if (deadTokenIds.length > 0) {
      const deadSet: Record<string, unknown> = {
        active: false,
        updatedAt: now,
      }
      // Any token whose Unregistered response carried a timestamp gets
      // that recorded; otherwise `unregisteredAt` falls back to `now`.
      deadSet.unregisteredAt = now
      await notificationTokens.updateMany(
        { _id: { $in: deadTokenIds } },
        { $set: deadSet },
      )
      logger.info('Marked APNs tokens dead after push', {
        jobId: job.id,
        userId,
        deadTokenCount: deadTokenIds.length,
      })
    }

    if (deliveredTokenIds.length > 0) {
      await notificationTokens.updateMany(
        { _id: { $in: deliveredTokenIds } },
        {
          $set: {
            lastUsedAt: now,
            updatedAt: now,
          },
        },
      )
    }

    logger.info('Push notification dispatch complete', {
      jobId: job.id,
      userId,
      type,
      attempted: tokens.length,
      delivered: deliveredTokenIds.length,
      dead: deadTokenIds.length,
    })
  })
}
