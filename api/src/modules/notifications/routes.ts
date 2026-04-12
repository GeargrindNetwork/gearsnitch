import { Router } from 'express'
import { Types } from 'mongoose'
import { StatusCodes } from 'http-status-codes'
import { z } from 'zod'
import { isAuthenticated } from '../../middleware/auth.js'
import {
  type INotificationLog,
  NotificationLog,
} from '../../models/NotificationLog.js'
import { NotificationToken } from '../../models/NotificationToken.js'
import { User } from '../../models/User.js'
import logger from '../../utils/logger.js'
import { errorResponse, successResponse } from '../../utils/response.js'

const router = Router()

interface SerializedNotificationToken {
  _id?: Types.ObjectId
  platform?: string
  environment?: string
  active?: boolean
}

const listNotificationsSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
  unreadOnly: z.preprocess((value) => {
    if (Array.isArray(value)) {
      return value[0]
    }

    if (typeof value === 'string') {
      const normalized = value.trim().toLowerCase()
      if (['true', '1', 'yes', 'on'].includes(normalized)) {
        return true
      }
      if (['false', '0', 'no', 'off', ''].includes(normalized)) {
        return false
      }
    }

    return value
  }, z.coerce.boolean().default(false)),
})

const updatePreferencesSchema = z
  .object({
    pushEnabled: z.boolean().optional(),
    panicAlertsEnabled: z.boolean().optional(),
    disconnectAlertsEnabled: z.boolean().optional(),
    custom: z.record(z.string()).optional(),
  })
  .refine(
    (value) => Object.values(value).some((field) => field !== undefined),
    'At least one preference field is required',
  )

const registerTokenSchema = z.object({
  token: z.string().min(16),
  platform: z.enum(['ios', 'watchos']).default('ios'),
  environment: z.enum(['sandbox', 'production']).optional(),
})

function serializeNotification(
  notification: INotificationLog & {
    tokenId?: Types.ObjectId | SerializedNotificationToken | null
  },
) {
  const token =
    typeof notification.tokenId === 'object' && notification.tokenId !== null
      ? (notification.tokenId as SerializedNotificationToken)
      : null

  return {
    _id: notification._id.toString(),
    notificationType: notification.notificationType,
    title: notification.title ?? null,
    body: notification.body ?? null,
    metadata: notification.metadata ?? null,
    sentAt: notification.sentAt,
    deliveredAt: notification.deliveredAt,
    openedAt: notification.openedAt,
    failureReason: notification.failureReason,
    status: notification.openedAt
      ? 'read'
      : notification.failureReason
        ? 'failed'
        : notification.deliveredAt
          ? 'delivered'
          : 'sent',
    token: token
      ? {
          _id: token._id?.toString() ?? null,
          platform: token.platform ?? null,
          environment: token.environment ?? null,
          active: token.active ?? null,
        }
      : null,
  }
}

function parseObjectId(id: string): Types.ObjectId | null {
  return Types.ObjectId.isValid(id) ? new Types.ObjectId(id) : null
}

// GET /notifications
router.get('/', isAuthenticated, async (req, res) => {
  try {
    const { page, limit, unreadOnly } = listNotificationsSchema.parse(req.query)
    const userId = parseObjectId(req.user!.sub)
    if (!userId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid user identifier')
      return
    }

    const filter: Record<string, unknown> = { userId }
    if (unreadOnly) {
      filter.openedAt = null
    }

    const skip = (page - 1) * limit
    const [notifications, total, unreadCount] = await Promise.all([
      NotificationLog.find(filter)
        .sort({ sentAt: -1 })
        .skip(skip)
        .limit(limit)
        .populate('tokenId', 'platform environment active')
        .exec(),
      NotificationLog.countDocuments(filter),
      NotificationLog.countDocuments({ userId, openedAt: null }),
    ])

    successResponse(
      res,
      notifications.map((notification) => serializeNotification(notification)),
      StatusCodes.OK,
      {
        page,
        limit,
        total,
        unreadCount,
      },
    )
  } catch (error) {
    if (error instanceof z.ZodError) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid notification query', error.flatten())
      return
    }

    logger.error('Failed to list notifications', { error })
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to list notifications')
  }
})

// PATCH /notifications/:id/read
router.patch('/:id/read', isAuthenticated, async (req, res) => {
  try {
    const userId = parseObjectId(req.user!.sub)
    const notificationParam = Array.isArray(req.params.id)
      ? req.params.id[0]
      : req.params.id
    const notificationId = parseObjectId(notificationParam)
    if (!userId || !notificationId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid notification identifier')
      return
    }

    const now = new Date()
    const notification = await NotificationLog.findOneAndUpdate(
      {
        _id: notificationId,
        userId,
      },
      {
        $set: {
          openedAt: now,
          deliveredAt: now,
        },
      },
      {
        new: true,
      },
    )
      .populate('tokenId', 'platform environment active')
      .exec()

    if (!notification) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Notification not found')
      return
    }

    successResponse(res, serializeNotification(notification), StatusCodes.OK)
  } catch (error) {
    logger.error('Failed to mark notification as read', { error })
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to mark notification as read')
  }
})

// POST /notifications/read-all
router.post('/read-all', isAuthenticated, async (req, res) => {
  try {
    const userId = parseObjectId(req.user!.sub)
    if (!userId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid user identifier')
      return
    }

    const now = new Date()
    const result = await NotificationLog.updateMany(
      {
        userId,
        openedAt: null,
      },
      {
        $set: {
          openedAt: now,
          deliveredAt: now,
        },
      },
    )

    successResponse(
      res,
      {
        matchedCount: result.matchedCount,
        modifiedCount: result.modifiedCount,
        openedAt: now,
      },
      StatusCodes.OK,
    )
  } catch (error) {
    logger.error('Failed to mark notifications as read', { error })
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to mark notifications as read')
  }
})

// GET /notifications/preferences
router.get('/preferences', isAuthenticated, async (req, res) => {
  try {
    const user = await User.findById(req.user!.sub)
      .select('preferences permissionsState')
      .lean()
      .exec()

    if (!user) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found')
      return
    }

    successResponse(
      res,
      {
        permissionsState: user.permissionsState ?? {
          bluetooth: false,
          location: false,
          notifications: false,
        },
        preferences: user.preferences ?? {
          pushEnabled: false,
          panicAlertsEnabled: false,
          disconnectAlertsEnabled: false,
          custom: {},
        },
      },
      StatusCodes.OK,
    )
  } catch (error) {
    logger.error('Failed to fetch notification preferences', { error })
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to fetch notification preferences')
  }
})

// PATCH /notifications/preferences
router.patch('/preferences', isAuthenticated, async (req, res) => {
  try {
    const body = updatePreferencesSchema.parse(req.body ?? {})
    const user = await User.findById(req.user!.sub).exec()

    if (!user) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found')
      return
    }

    const existingPreferences = user.preferences ?? {
      pushEnabled: false,
      panicAlertsEnabled: false,
      disconnectAlertsEnabled: false,
      custom: {},
    }

    user.preferences = {
      pushEnabled: body.pushEnabled ?? existingPreferences.pushEnabled ?? false,
      panicAlertsEnabled:
        body.panicAlertsEnabled ?? existingPreferences.panicAlertsEnabled ?? false,
      disconnectAlertsEnabled:
        body.disconnectAlertsEnabled
        ?? existingPreferences.disconnectAlertsEnabled
        ?? false,
      custom: {
        ...(existingPreferences.custom ?? {}),
        ...(body.custom ?? {}),
      },
    }

    await user.save()

    successResponse(
      res,
      {
        permissionsState: user.permissionsState,
        preferences: user.preferences,
      },
      StatusCodes.OK,
    )
  } catch (error) {
    if (error instanceof z.ZodError) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'Invalid notification preferences payload',
        error.flatten(),
      )
      return
    }

    logger.error('Failed to update notification preferences', { error })
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to update notification preferences')
  }
})

// POST /notifications/register
router.post('/register', isAuthenticated, async (req, res) => {
  try {
    const body = registerTokenSchema.parse(req.body ?? {})
    const userId = parseObjectId(req.user!.sub)
    if (!userId) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid user identifier')
      return
    }

    const now = new Date()
    await NotificationToken.updateMany(
      {
        userId,
        platform: body.platform,
        token: { $ne: body.token },
      },
      {
        $set: {
          active: false,
          updatedAt: now,
        },
      },
    )

    const token = await NotificationToken.findOneAndUpdate(
      { token: body.token },
      {
        $set: {
          userId,
          platform: body.platform,
          environment:
            body.environment
            ?? (process.env.NODE_ENV === 'production' ? 'production' : 'sandbox'),
          active: true,
          lastUsedAt: now,
        },
      },
      {
        new: true,
        upsert: true,
        setDefaultsOnInsert: true,
      },
    ).exec()

    successResponse(
      res,
      {
        _id: token._id.toString(),
        platform: token.platform,
        environment: token.environment,
        active: token.active,
        lastUsedAt: token.lastUsedAt,
      },
      StatusCodes.OK,
    )
  } catch (error) {
    if (error instanceof z.ZodError) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'Invalid notification token payload',
        error.flatten(),
      )
      return
    }

    logger.error('Failed to register notification token', { error })
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to register notification token')
  }
})

export default router
