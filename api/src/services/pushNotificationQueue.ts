import { Queue } from 'bullmq';
import IORedis from 'ioredis';
import config from '../config/index.js';
import logger from '../utils/logger.js';

/**
 * Thin API-side wrapper around the BullMQ `push-notifications` queue that
 * the worker drains via `worker/src/jobs/pushNotification.ts` (PR #48).
 *
 * Mirrors `enqueueJob('push-notifications', ...)` from
 * `worker/src/utils/jobRuntime.ts` — kept on the API side so route handlers
 * don't need to import the worker package.
 *
 * The Redis connection here is dedicated (raw IORedis, no key-prefix) so
 * BullMQ's keyspace stays compatible with the worker. The shared
 * `getRedisClient()` is configured with `keyPrefix: 'gs:'` and is therefore
 * not safe to hand to BullMQ — BullMQ would double-prefix and the worker
 * would never see the jobs.
 */

const PUSH_QUEUE_NAME = 'push-notifications';

let queueConnection: IORedis | null = null;
let queue: Queue | null = null;
let testEnqueueOverride: ((job: PushNotificationJobData) => Promise<void>) | null = null;

export interface PushNotificationJobData {
  userId: string;
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  dedupeKey?: string;
}

function getQueueConnection(): IORedis {
  if (!queueConnection) {
    if (!config.redisUrl) {
      throw new Error('REDIS_URL is not configured');
    }
    // BullMQ requires `maxRetriesPerRequest: null` and works directly with
    // the raw key-space (no `gs:` prefix) so the worker side sees the jobs.
    queueConnection = new IORedis(config.redisUrl, {
      maxRetriesPerRequest: null,
    });
  }
  return queueConnection;
}

function getPushQueue(): Queue {
  if (!queue) {
    queue = new Queue(PUSH_QUEUE_NAME, { connection: getQueueConnection() });
  }
  return queue;
}

/**
 * Enqueue a push notification job for the worker to deliver via APNs.
 *
 * In tests, callers may swap the implementation via
 * `__setPushNotificationEnqueueOverrideForTests` so they can assert what
 * would have been enqueued without needing a real Redis.
 */
export async function enqueuePushNotification(
  payload: PushNotificationJobData,
): Promise<void> {
  if (testEnqueueOverride) {
    await testEnqueueOverride(payload);
    return;
  }

  try {
    await getPushQueue().add(PUSH_QUEUE_NAME, payload, {
      jobId: payload.dedupeKey,
      attempts: 3,
      backoff: { type: 'exponential', delay: 1_000 },
      removeOnComplete: 50,
      removeOnFail: 100,
    });
  } catch (err) {
    logger.error('Failed to enqueue push notification', {
      userId: payload.userId,
      type: payload.type,
      error: err instanceof Error ? err.message : String(err),
    });
    throw err;
  }
}

/**
 * Test-only hook. Pass a function to capture enqueue calls; pass `null` to
 * restore the real queue. Underscore-prefixed to mirror the convention used
 * by `worker/src/utils/apnsClient.ts`.
 */
export function __setPushNotificationEnqueueOverrideForTests(
  override: ((job: PushNotificationJobData) => Promise<void>) | null,
): void {
  testEnqueueOverride = override;
}

export async function shutdownPushNotificationQueue(): Promise<void> {
  if (queue) {
    await queue.close();
    queue = null;
  }
  if (queueConnection) {
    await queueConnection.quit();
    queueConnection = null;
  }
}
