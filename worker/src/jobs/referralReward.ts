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

interface ReferralRewardJobData {
  referralId: string
  referrerUserId: string
}

function addDays(baseDate: Date, days: number): Date {
  return new Date(baseDate.getTime() + days * 24 * 60 * 60 * 1000)
}

export async function processReferralReward(
  job: Job<ReferralRewardJobData>,
): Promise<void> {
  const data = recordFromUnknown(job.data)
  const referralId = requireString(data, 'referralId')
  const referrerUserId = requireString(data, 'referrerUserId')

  await withIdempotency(
    'referral-reward',
    hashDedupeKey([referralId, referrerUserId]),
    async () => {
      const referrals = getCollection('referrals')
      const subscriptions = getCollection('subscriptions')
      const now = new Date()
      const referralIdObject = toObjectId(referralId)
      const referrerUserIdObject = toObjectId(referrerUserId)

      const referral = await referrals.findOne({ _id: referralIdObject })
      if (!referral) {
        logger.warn('Skipping referral reward for missing referral', {
          jobId: job.id,
          referralId,
          referrerUserId,
        })
        return
      }

      if (referral.status === 'rewarded') {
        logger.info('Referral reward already applied', {
          jobId: job.id,
          referralId,
        })
        return
      }

      if (referral.status !== 'qualified') {
        logger.warn('Referral reward skipped because the referral is not qualified', {
          jobId: job.id,
          referralId,
          status: referral.status,
        })
        return
      }

      const subscription = await subscriptions.findOne(
        {
          userId: referrerUserIdObject,
          status: { $in: ['active', 'grace_period'] },
        },
        { sort: { expiryDate: -1 } },
      )

      if (!subscription) {
        logger.warn('Referral reward could not be applied because no subscription exists', {
          jobId: job.id,
          referralId,
          referrerUserId,
        })
        return
      }

      const rewardDays =
        typeof referral.rewardDays === 'number' && referral.rewardDays > 0
          ? referral.rewardDays
          : 28

      const currentExpiry =
        subscription.expiryDate instanceof Date
          ? subscription.expiryDate
          : new Date(subscription.expiryDate)
      const nextExpiry = addDays(
        currentExpiry > now ? currentExpiry : now,
        rewardDays,
      )

      await subscriptions.updateOne(
        { _id: subscription._id },
        {
          $set: {
            expiryDate: nextExpiry,
            lastValidatedAt: now,
            status: 'active',
            updatedAt: now,
          },
          $inc: {
            extensionDays: rewardDays,
          },
        },
      )

      await referrals.updateOne(
        { _id: referralIdObject },
        {
          $set: {
            status: 'rewarded',
            rewardedAt: now,
            reason: null,
            updatedAt: now,
          },
        },
      )

      await enqueueJob(
        'push-notifications',
        {
          userId: referrerUserId,
          type: 'referral_reward',
          title: 'Referral reward unlocked',
          body: `You earned ${rewardDays} bonus days on your subscription.`,
          data: {
            referralId,
            expiresAt: nextExpiry.toISOString(),
          },
          dedupeKey: `referral-reward:${referralId}`,
        },
        `push-referral-reward:${referralId}`,
      )

      await publishRuntimeEvent('events:referral', {
        userId: referrerUserId,
        target: 'user',
        eventName: 'referral:update',
        payload: {
          referralId,
          type: 'rewarded',
          referrerUserId,
          referredUserId: referral.referredUserId?.toString() ?? null,
          rewardAmount: rewardDays,
        },
      })

      logger.info('Referral reward applied', {
        jobId: job.id,
        referralId,
        referrerUserId,
        rewardDays,
      })
    },
  )
}
