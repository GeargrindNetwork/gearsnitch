import http from 'http'
import { Server, type Namespace, type Socket } from 'socket.io'
import { createAdapter } from '@socket.io/redis-adapter'
import IORedis from 'ioredis'
import mongoose, { Types } from 'mongoose'
import { z } from 'zod'
import { logger } from './utils/logger'
import { authenticateSocketSession } from './utils/socketAuth'
import {
  EVENT_CHANNELS,
  type EventChannel,
  parseRuntimeEvent,
  roomForEvent,
} from './utils/runtimeEvents'

const PORT = parseInt(process.env.PORT || '3002', 10)
const MONGODB_URI = process.env.MONGODB_URI || ''
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379'
const JWT_PRIVATE_KEY = process.env.JWT_PRIVATE_KEY || ''
const JWT_PUBLIC_KEY = process.env.JWT_PUBLIC_KEY || ''
const IS_PRODUCTION = process.env.NODE_ENV === 'production'
const CORS_ORIGINS = (process.env.CORS_ORIGINS || 'http://localhost:5173').split(',')

const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200)
    res.end('OK')
    return
  }

  res.writeHead(404)
  res.end()
})

const io = new Server(httpServer, {
  cors: {
    origin: CORS_ORIGINS,
    credentials: true,
  },
  pingTimeout: 60_000,
  pingInterval: 25_000,
})

const adapterPubClient = new IORedis(REDIS_URL, { maxRetriesPerRequest: null })
const adapterSubClient = adapterPubClient.duplicate()
const eventPublisher = new IORedis(REDIS_URL, { maxRetriesPerRequest: null })
const eventSubscriber = new IORedis(REDIS_URL, { maxRetriesPerRequest: null })
const stateRedis = new IORedis(REDIS_URL, {
  keyPrefix: 'gs:',
  maxRetriesPerRequest: null,
})

io.adapter(createAdapter(adapterPubClient, adapterSubClient))

const userNs = io.of('/user')
const deviceNs = io.of('/devices')

const alertAckSchema = z.object({
  alertId: z.string().min(1),
})

const deviceStatusUpdateSchema = z.object({
  deviceId: z.string().min(1),
  status: z.enum([
    'registered',
    'active',
    'inactive',
    'connected',
    'monitoring',
    'disconnected',
    'lost',
    'reconnected',
  ]),
  lastSignalStrength: z.number().int().min(-150).max(0).optional(),
  lastSeenLocation: z
    .object({
      type: z.literal('Point'),
      coordinates: z.tuple([z.number(), z.number()]),
    })
    .optional(),
})

function toObjectId(value: string): Types.ObjectId {
  if (!Types.ObjectId.isValid(value)) {
    throw new Error(`Invalid ObjectId: ${value}`)
  }

  return new Types.ObjectId(value)
}

function alertsCollection() {
  return mongoose.connection.collection('alerts')
}

function devicesCollection() {
  return mongoose.connection.collection('devices')
}

function deviceSharesCollection() {
  return mongoose.connection.collection('deviceshares')
}

function serializeDeviceState(device: Record<string, unknown>) {
  const deviceId =
    device._id instanceof Types.ObjectId ? device._id.toString() : String(device._id)

  return {
    deviceId,
    name: typeof device.name === 'string' ? device.name : 'Unnamed device',
    status: typeof device.status === 'string' ? device.status : 'inactive',
    rssi:
      typeof device.lastSignalStrength === 'number'
        ? device.lastSignalStrength
        : null,
    lastSeenAt:
      device.lastSeenAt instanceof Date
        ? device.lastSeenAt.toISOString()
        : device.lastSeenAt ?? null,
  }
}

async function publishRuntimeEvent(
  channel: EventChannel,
  event: {
    userId: string
    target: 'user' | 'devices'
    eventName: string
    payload: Record<string, unknown>
    dedupeKey?: string
  },
): Promise<void> {
  await eventPublisher.publish(
    channel,
    JSON.stringify({
      ...event,
      emittedAt: new Date().toISOString(),
    }),
  )
}

async function resolveDeviceAudienceUserIds(
  deviceId: string,
  ownerUserId: string,
): Promise<string[]> {
  const deviceIdObject = toObjectId(deviceId)
  const shares = await deviceSharesCollection()
    .find({ deviceId: deviceIdObject })
    .project({ sharedWithUserId: 1 })
    .toArray()

  return Array.from(
    new Set([
      ownerUserId,
      ...shares
        .map((share) =>
          share.sharedWithUserId instanceof Types.ObjectId
            ? share.sharedWithUserId.toString()
            : null,
        )
        .filter((value): value is string => Boolean(value)),
    ]),
  )
}

async function loadVisibleDevicesForUser(userId: string) {
  const userIdObject = toObjectId(userId)

  const [ownedDevices, sharedRows] = await Promise.all([
    devicesCollection().find({ userId: userIdObject }).toArray(),
    deviceSharesCollection()
      .find({ sharedWithUserId: userIdObject })
      .project({ deviceId: 1 })
      .toArray(),
  ])

  const sharedDeviceIds = sharedRows
    .map((row) => row.deviceId)
    .filter((value): value is Types.ObjectId => value instanceof Types.ObjectId)

  const sharedDevices =
    sharedDeviceIds.length > 0
      ? await devicesCollection()
          .find({ _id: { $in: sharedDeviceIds } })
          .toArray()
      : []

  const deduped = new Map<string, Record<string, unknown>>()
  for (const device of [...ownedDevices, ...sharedDevices]) {
    const key =
      device._id instanceof Types.ObjectId ? device._id.toString() : String(device._id)
    deduped.set(key, device)
  }

  return Array.from(deduped.values()).map(serializeDeviceState)
}

function applyNamespaceAuth(namespace: Namespace) {
  namespace.use(async (socket, next) => {
    try {
      await authenticateSocketSession(
        socket,
        stateRedis,
        JWT_PRIVATE_KEY,
        JWT_PUBLIC_KEY,
        IS_PRODUCTION,
      )
      next()
    } catch (error) {
      next(error instanceof Error ? error : new Error('Authentication failed'))
    }
  })
}

io.use(async (socket, next) => {
  try {
    await authenticateSocketSession(
      socket,
      stateRedis,
      JWT_PRIVATE_KEY,
      JWT_PUBLIC_KEY,
      IS_PRODUCTION,
    )
    next()
  } catch (error) {
    next(error instanceof Error ? error : new Error('Authentication failed'))
  }
})

applyNamespaceAuth(userNs)
applyNamespaceAuth(deviceNs)

io.on('connection', (socket) => {
  const userId = socket.data.userId as string
  socket.join(`user:${userId}`)
  logger.info(`Default realtime socket connected: ${userId}`)

  socket.on('disconnect', () => {
    logger.info(`Default realtime socket disconnected: ${userId}`)
  })
})

userNs.on('connection', (socket) => {
  const userId = socket.data.userId as string
  socket.join(`user:${userId}`)
  logger.info(`User namespace connected: ${userId}`)

  socket.on('user:presence', async () => {
    await stateRedis.setex(`presence:user:${userId}`, 120, 'online')
  })

  socket.on('alerts:ack', async (payload) => {
    const parsed = alertAckSchema.safeParse(payload)
    if (!parsed.success) {
      socket.emit('alert:error', {
        message: 'Invalid alert acknowledgement payload',
      })
      return
    }

    const now = new Date()
    const result = await alertsCollection().findOneAndUpdate(
      {
        _id: toObjectId(parsed.data.alertId),
        userId: toObjectId(userId),
      },
      {
        $set: {
          status: 'acknowledged',
          updatedAt: now,
        },
      },
      {
        returnDocument: 'after',
      },
    )

    if (!result) {
      socket.emit('alert:error', {
        message: 'Alert not found',
        alertId: parsed.data.alertId,
      })
      return
    }

    socket.emit('alert:acknowledged', {
      alertId: parsed.data.alertId,
      status: 'acknowledged',
      timestamp: now.toISOString(),
    })
  })

  socket.on('disconnect', () => {
    logger.info(`User namespace disconnected: ${userId}`)
  })
})

deviceNs.on('connection', (socket) => {
  const userId = socket.data.userId as string
  socket.join(`devices:${userId}`)
  logger.info(`Devices namespace connected: ${userId}`)

  const emitDeviceSync = async () => {
    const devices = await loadVisibleDevicesForUser(userId)
    socket.emit('device:sync', {
      items: devices,
      syncedAt: new Date().toISOString(),
    })
  }

  void emitDeviceSync()

  socket.on('device:status:update', async (payload) => {
    const parsed = deviceStatusUpdateSchema.safeParse(payload)
    if (!parsed.success) {
      socket.emit('device:error', {
        message: 'Invalid device status payload',
      })
      return
    }

    const now = new Date()
    const update = parsed.data
    const deviceIdObject = toObjectId(update.deviceId)

    const existingDevice = await devicesCollection().findOne({
      _id: deviceIdObject,
      userId: toObjectId(userId),
    })

    if (!existingDevice) {
      socket.emit('device:error', {
        message: 'Device not found',
        deviceId: update.deviceId,
      })
      return
    }

    await devicesCollection().updateOne(
      { _id: deviceIdObject },
      {
        $set: {
          status: update.status,
          lastSeenAt: now,
          ...(update.lastSeenLocation ? { lastSeenLocation: update.lastSeenLocation } : {}),
          ...(update.lastSignalStrength !== undefined
            ? { lastSignalStrength: update.lastSignalStrength }
            : {}),
          updatedAt: now,
        },
      },
    )

    const audienceUserIds = await resolveDeviceAudienceUserIds(update.deviceId, userId)
    for (const audienceUserId of audienceUserIds) {
      await publishRuntimeEvent('events:device-status', {
        userId: audienceUserId,
        target: 'devices',
        eventName: 'device:status',
        payload: {
          deviceId: update.deviceId,
          status: update.status,
          rssi: update.lastSignalStrength ?? null,
          timestamp: now.toISOString(),
        },
        dedupeKey: `${update.deviceId}:${audienceUserId}:${now.toISOString()}`,
      })
    }

    socket.emit('device:status:accepted', {
      deviceId: update.deviceId,
      status: update.status,
      timestamp: now.toISOString(),
    })
  })

  socket.on('device:sync', async () => {
    await emitDeviceSync()
  })

  socket.on('disconnect', () => {
    logger.info(`Devices namespace disconnected: ${userId}`)
  })
})

eventSubscriber.on('message', (channel, message) => {
  try {
    const event = parseRuntimeEvent(message)
    const room = roomForEvent(event)

    switch (channel as EventChannel) {
      case 'events:device-status':
        deviceNs.to(room).emit(event.eventName, event.payload)
        break
      case 'events:alert':
      case 'events:subscription':
      case 'events:referral':
      case 'events:store-order':
        io.to(room).emit(event.eventName, event.payload)
        userNs.to(room).emit(event.eventName, event.payload)
        break
      default:
        logger.warn('Ignoring unsupported realtime event channel', { channel })
    }
  } catch (error) {
    logger.error('Failed to process pub/sub event', { channel, error })
  }
})

async function start() {
  await mongoose.connect(MONGODB_URI)
  logger.info('Connected to MongoDB')

  await eventSubscriber.subscribe(...EVENT_CHANNELS)
  logger.info('Subscribed to realtime event channels', { channels: EVENT_CHANNELS })

  httpServer.listen(PORT, () => {
    logger.info(`GearSnitch Realtime service running on port ${PORT}`)
  })
}

async function shutdown() {
  logger.info('Realtime service shutting down...')
  io.close()
  await Promise.all([
    eventSubscriber.quit(),
    eventPublisher.quit(),
    stateRedis.quit(),
    adapterPubClient.quit(),
    adapterSubClient.quit(),
  ])
  await mongoose.disconnect()
  httpServer.close()
  process.exit(0)
}

process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)

start().catch((error) => {
  logger.error('Realtime service failed to start', { error })
  process.exit(1)
})
