import crypto from 'node:crypto'
import { Queue } from 'bullmq'
import IORedis from 'ioredis'
import mongoose, { Types } from 'mongoose'
import { logger } from './logger'

const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379'
const IDEMPOTENCY_TTL_SECONDS = 60 * 60

export const WORKER_QUEUE_NAMES = [
  'referral-qualification',
  'referral-reward',
  'subscription-validation',
  'push-notifications',
  'alert-fanout',
  'store-order-processing',
  'data-export',
] as const

export type WorkerQueueName = (typeof WORKER_QUEUE_NAMES)[number]

export const WORKER_EVENT_CHANNELS = [
  'events:device-status',
  'events:alert',
  'events:subscription',
  'events:referral',
  'events:store-order',
] as const

export type WorkerEventChannel = (typeof WORKER_EVENT_CHANNELS)[number]

export interface WorkerRuntimeEvent {
  userId: string
  target: 'user' | 'devices'
  eventName: string
  payload: Record<string, unknown>
  emittedAt?: string
  dedupeKey?: string
}

let redisConnection: IORedis | null = null
const queues = new Map<WorkerQueueName, Queue>()

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export function recordFromUnknown(value: unknown): Record<string, unknown> {
  return isRecord(value) ? value : {}
}

export function getRedisConnection(): IORedis {
  if (!redisConnection) {
    redisConnection = new IORedis(REDIS_URL, { maxRetriesPerRequest: null })
  }

  return redisConnection
}

function getQueue(queueName: WorkerQueueName): Queue {
  const existing = queues.get(queueName)
  if (existing) {
    return existing
  }

  const queue = new Queue(queueName, { connection: getRedisConnection() })
  queues.set(queueName, queue)
  return queue
}

function getDb() {
  if (!mongoose.connection.db) {
    throw new Error('MongoDB is not connected')
  }

  return mongoose.connection.db
}

export function getCollection(name: string) {
  return getDb().collection(name)
}

export function toObjectId(value: string): Types.ObjectId {
  if (!Types.ObjectId.isValid(value)) {
    throw new Error(`Invalid ObjectId: ${value}`)
  }

  return new Types.ObjectId(value)
}

export function requireString(
  data: Record<string, unknown>,
  field: string,
): string {
  const value = data[field]
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Expected non-empty string for "${field}"`)
  }

  return value
}

export function optionalString(
  data: Record<string, unknown>,
  field: string,
): string | undefined {
  const value = data[field]
  if (value === undefined || value === null) {
    return undefined
  }

  if (typeof value !== 'string') {
    throw new Error(`Expected string for "${field}"`)
  }

  return value
}

export function optionalRecord(
  data: Record<string, unknown>,
  field: string,
): Record<string, unknown> | undefined {
  const value = data[field]
  if (value === undefined || value === null) {
    return undefined
  }

  if (!isRecord(value)) {
    throw new Error(`Expected object for "${field}"`)
  }

  return value
}

export function hashDedupeKey(parts: Array<string | number | null | undefined>): string {
  const normalized = parts
    .map((part) => (part === undefined || part === null ? '' : String(part)))
    .join(':')

  return crypto.createHash('sha1').update(normalized).digest('hex')
}

export async function withIdempotency(
  queueName: WorkerQueueName,
  dedupeKey: string,
  execute: () => Promise<void>,
): Promise<boolean> {
  const redis = getRedisConnection()
  const claimKey = `gs:worker:${queueName}:${dedupeKey}`
  const claimed = await redis.set(
    claimKey,
    new Date().toISOString(),
    'EX',
    IDEMPOTENCY_TTL_SECONDS,
    'NX',
  )

  if (!claimed) {
    logger.warn('Skipping duplicate worker job', { queueName, dedupeKey })
    return false
  }

  try {
    await execute()
    return true
  } catch (error) {
    await redis.del(claimKey).catch(() => undefined)
    throw error
  }
}

export async function enqueueJob(
  queueName: WorkerQueueName,
  data: Record<string, unknown>,
  jobId?: string,
): Promise<void> {
  await getQueue(queueName).add(queueName, data, {
    jobId,
    attempts: 3,
    backoff: { type: 'exponential', delay: 1_000 },
    removeOnComplete: 50,
    removeOnFail: 100,
  })
}

export async function publishRuntimeEvent(
  channel: WorkerEventChannel,
  event: WorkerRuntimeEvent,
): Promise<void> {
  if (!WORKER_EVENT_CHANNELS.includes(channel)) {
    throw new Error(`Unsupported event channel: ${channel}`)
  }

  if (!event.userId || !event.eventName) {
    throw new Error('Realtime events require userId and eventName')
  }

  await getRedisConnection().publish(
    channel,
    JSON.stringify({
      ...event,
      emittedAt: event.emittedAt ?? new Date().toISOString(),
    }),
  )
}

export async function shutdownJobRuntime(): Promise<void> {
  await Promise.all(Array.from(queues.values()).map((queue) => queue.close()))
  queues.clear()

  if (redisConnection) {
    await redisConnection.quit()
    redisConnection = null
  }
}
