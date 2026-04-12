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

interface AlertFanoutJobData {
  alertId: string
  userId: string
  type: string
  severity: string
  deviceId?: string
}

function buildAlertMessage(type: string, severity: string): string {
  switch (type) {
    case 'panic_alarm':
      return 'Panic alarm triggered. Open the app immediately.'
    case 'disconnect_warning':
    case 'device_disconnected':
      return 'A monitored device disconnected unexpectedly.'
    case 'reconnect_found':
      return 'A previously disconnected device reconnected.'
    case 'gym_entry_activate':
      return 'Gym monitoring activated from a geofence entry.'
    case 'gym_exit_deactivate':
      return 'Gym monitoring deactivated after leaving the geofence.'
    default:
      return `Alert received (${type}, ${severity}).`
  }
}

export async function processAlertFanout(job: Job<AlertFanoutJobData>): Promise<void> {
  const data = recordFromUnknown(job.data)
  const alertId = requireString(data, 'alertId')
  const userId = requireString(data, 'userId')
  const type = requireString(data, 'type')
  const severity = requireString(data, 'severity')
  const deviceId = typeof data.deviceId === 'string' ? data.deviceId : undefined

  await withIdempotency(
    'alert-fanout',
    hashDedupeKey([alertId, userId, type, severity]),
    async () => {
      const alerts = getCollection('alerts')
      const users = getCollection('users')
      const emergencyContacts = getCollection('emergencycontacts')

      const alert = await alerts.findOne({
        _id: toObjectId(alertId),
        userId: toObjectId(userId),
      })

      const alertMessage = buildAlertMessage(type, severity)
      await publishRuntimeEvent('events:alert', {
        userId,
        target: 'user',
        eventName: 'alert:new',
        payload: {
          alertId,
          type,
          message: alertMessage,
          severity,
          deviceId: deviceId ?? (alert?.deviceId?.toString() as string | undefined),
          timestamp: (alert?.triggeredAt instanceof Date
            ? alert.triggeredAt.toISOString()
            : new Date().toISOString()),
        },
      })

      const user = await users.findOne(
        { _id: toObjectId(userId) },
        { projection: { preferences: 1 } },
      )

      const preferences =
        typeof user?.preferences === 'object' && user.preferences !== null
          ? (user.preferences as Record<string, unknown>)
          : {}

      const shouldQueuePush =
        preferences.pushEnabled === true
        && !(type === 'panic_alarm' && preferences.panicAlertsEnabled === false)
        && !(
          (type === 'disconnect_warning' || type === 'device_disconnected')
          && preferences.disconnectAlertsEnabled === false
        )

      if (shouldQueuePush) {
        await enqueueJob(
          'push-notifications',
          {
            userId,
            type,
            title: severity === 'critical' ? 'Critical GearSnitch alert' : 'GearSnitch alert',
            body: alertMessage,
            data: {
              alertId,
              type,
              severity,
              ...(deviceId ? { deviceId } : {}),
            },
            dedupeKey: `alert:${alertId}`,
          },
          `push-alert:${alertId}`,
        )
      }

      const emergencyContactCount = await emergencyContacts.countDocuments({
        userId: toObjectId(userId),
        $or: [
          { notifyOnPanic: type === 'panic_alarm' },
          { notifyOnDisconnect: type === 'disconnect_warning' || type === 'device_disconnected' },
        ],
      })

      logger.info('Alert fanout processed', {
        jobId: job.id,
        alertId,
        userId,
        type,
        severity,
        pushQueued: shouldQueuePush,
        emergencyContactCount,
      })
    },
  )
}
