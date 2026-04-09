import mongoose from 'mongoose';
import { Worker } from 'bullmq';
import IORedis from 'ioredis';
import { logger } from './utils/logger';

const MONGODB_URI = process.env.MONGODB_URI || '';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';

const redisConnection = new IORedis(REDIS_URL, { maxRetriesPerRequest: null });

// Queue definitions matching the spec
const QUEUES = [
  'referral-qualification',
  'referral-reward',
  'subscription-validation',
  'subscription-reconciliation',
  'push-notifications',
  'emergency-contact-alert',
  'device-event-processing',
  'alert-fanout',
  'store-order-processing',
  'store-inventory-sync',
  'audit-export',
  'analytics-events',
  'data-export',
] as const;

type QueueName = (typeof QUEUES)[number];

// Import job processors
import { processReferralQualification } from './jobs/referralQualification';
import { processReferralReward } from './jobs/referralReward';
import { processPushNotification } from './jobs/pushNotification';
import { processSubscriptionValidation } from './jobs/subscriptionValidation';
import { processAlertFanout } from './jobs/alertFanout';
import { processStoreOrder } from './jobs/storeOrder';
import { processDataExport } from './jobs/dataExport';

const processors: Partial<Record<QueueName, (job: unknown) => Promise<void>>> = {
  'referral-qualification': processReferralQualification,
  'referral-reward': processReferralReward,
  'push-notifications': processPushNotification,
  'subscription-validation': processSubscriptionValidation,
  'alert-fanout': processAlertFanout,
  'store-order-processing': processStoreOrder,
  'data-export': processDataExport,
};

const workers: Worker[] = [];

async function start() {
  logger.info('GearSnitch Worker starting...');

  // Connect to MongoDB
  await mongoose.connect(MONGODB_URI);
  logger.info('Connected to MongoDB');

  // Start workers for each queue that has a processor
  for (const [queueName, processor] of Object.entries(processors)) {
    const worker = new Worker(
      queueName,
      async (job) => {
        logger.info(`Processing job ${job.id} on queue ${queueName}`);
        await processor(job);
      },
      {
        connection: redisConnection,
        concurrency: 1,
        limiter: { max: 10, duration: 1000 },
      }
    );

    worker.on('completed', (job) => {
      logger.info(`Job ${job?.id} completed on queue ${queueName}`);
    });

    worker.on('failed', (job, err) => {
      logger.error(`Job ${job?.id} failed on queue ${queueName}`, { error: err.message });
    });

    workers.push(worker);
    logger.info(`Worker started for queue: ${queueName}`);
  }

  logger.info(`GearSnitch Worker running with ${workers.length} queue processors`);
}

async function shutdown() {
  logger.info('Worker shutting down...');
  await Promise.all(workers.map((w) => w.close()));
  await mongoose.disconnect();
  await redisConnection.quit();
  logger.info('Worker shut down cleanly');
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

start().catch((err) => {
  logger.error('Worker failed to start', { error: err });
  process.exit(1);
});
