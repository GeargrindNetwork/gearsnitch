import type { Job } from 'bullmq'
import {
  enqueueJob,
  getCollection,
  getRedisConnection,
  hashDedupeKey,
  recordFromUnknown,
  requireString,
  toObjectId,
  withIdempotency,
} from '../utils/jobRuntime'
import { logger } from '../utils/logger'

interface DataExportJobData {
  userId: string
  requestId: string
}

export async function processDataExport(job: Job<DataExportJobData>): Promise<void> {
  const data = recordFromUnknown(job.data)
  const userId = requireString(data, 'userId')
  const requestId = requireString(data, 'requestId')

  await withIdempotency(
    'data-export',
    hashDedupeKey([userId, requestId]),
    async () => {
      const userIdObject = toObjectId(userId)
      const users = getCollection('users')
      const devices = getCollection('devices')
      const alerts = getCollection('alerts')
      const workouts = getCollection('workouts')
      const runs = getCollection('runs')
      const orders = getCollection('storeorders')
      const referrals = getCollection('referrals')
      const subscriptions = getCollection('subscriptions')
      const notificationLogs = getCollection('notificationlogs')

      const [
        user,
        deviceCount,
        alertCount,
        workoutCount,
        runCount,
        orderCount,
        referralCount,
        subscriptionCount,
        notificationCount,
      ] = await Promise.all([
        users.findOne(
          { _id: userIdObject },
          {
            projection: {
              email: 1,
              displayName: 1,
              createdAt: 1,
              preferences: 1,
              permissionsState: 1,
            },
          },
        ),
        devices.countDocuments({ userId: userIdObject }),
        alerts.countDocuments({ userId: userIdObject }),
        workouts.countDocuments({ userId: userIdObject }),
        runs.countDocuments({ userId: userIdObject }),
        orders.countDocuments({ userId: userIdObject }),
        referrals.countDocuments({
          $or: [
            { referrerUserId: userIdObject },
            { referredUserId: userIdObject },
          ],
        }),
        subscriptions.countDocuments({ userId: userIdObject }),
        notificationLogs.countDocuments({ userId: userIdObject }),
      ])

      const snapshot = {
        requestId,
        generatedAt: new Date().toISOString(),
        userId,
        profile: user
          ? {
              email: user.email,
              displayName: user.displayName,
              createdAt:
                user.createdAt instanceof Date
                  ? user.createdAt.toISOString()
                  : user.createdAt,
              preferences: user.preferences ?? {},
              permissionsState: user.permissionsState ?? {},
            }
          : null,
        counts: {
          devices: deviceCount,
          alerts: alertCount,
          workouts: workoutCount,
          runs: runCount,
          orders: orderCount,
          referrals: referralCount,
          subscriptions: subscriptionCount,
          notifications: notificationCount,
        },
      }

      await getRedisConnection().set(
        `gs:data-export:${requestId}`,
        JSON.stringify(snapshot),
        'EX',
        24 * 60 * 60,
      )

      await enqueueJob(
        'push-notifications',
        {
          userId,
          type: 'data_export',
          title: 'Your data export is ready',
          body: 'Open GearSnitch to review or download your export snapshot.',
          data: {
            requestId,
          },
          dedupeKey: `data-export:${requestId}`,
        },
        `push-data-export:${requestId}`,
      )

      logger.info('Data export snapshot generated', {
        jobId: job.id,
        userId,
        requestId,
      })
    },
  )
}
