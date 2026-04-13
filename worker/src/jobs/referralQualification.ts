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

interface ReferralQualificationJobData {
  referralId: string
  userId: string
}

export async function processReferralQualification(
  job: Job<ReferralQualificationJobData>,
): Promise<void> {
  const data = recordFromUnknown(job.data)
  const referralId = requireString(data, 'referralId')
  const userId = requireString(data, 'userId')

  await withIdempotency(
    'referral-qualification',
    hashDedupeKey([referralId, userId]),
    async () => {
      const referrals = getCollection('referrals')
      const subscriptions = getCollection('subscriptions')
      const now = new Date()
      const referralIdObject = toObjectId(referralId)
      const referredUserIdObject = toObjectId(userId)

      const referral = await referrals.findOne({ _id: referralIdObject })
      if (!referral) {
        logger.warn('Skipping referral qualification for missing referral', {
          jobId: job.id,
          referralId,
          userId,
        })
        return
      }

      if (referral.status === 'rewarded' || referral.status === 'qualified') {
        logger.info('Referral qualification already completed', {
          jobId: job.id,
          referralId,
          status: referral.status,
        })
        return
      }

      const qualifyingSubscription = await subscriptions.findOne({
        userId: referredUserIdObject,
        status: { $in: ['active', 'grace_period'] },
      })

      if (!qualifyingSubscription) {
        await referrals.updateOne(
          { _id: referralIdObject },
          {
            $set: {
              referredUserId: referredUserIdObject,
              reason: 'Awaiting qualifying subscription',
              updatedAt: now,
            },
          },
        )

        logger.info('Referral remains pending without a qualifying subscription', {
          jobId: job.id,
          referralId,
          userId,
        })
        return
      }

      await referrals.updateOne(
        { _id: referralIdObject },
        {
          $set: {
            referredUserId: referredUserIdObject,
            status: 'qualified',
            qualifiedAt: now,
            reason: null,
            updatedAt: now,
          },
        },
      )

      const referrerUserId = referral.referrerUserId.toString()
      await enqueueJob(
        'referral-reward',
        {
          referralId,
          referrerUserId,
        },
        `referral-reward:${referralId}`,
      )

      await publishRuntimeEvent('events:referral', {
        userId: referrerUserId,
        target: 'user',
        eventName: 'referral:update',
        payload: {
          referralId,
          type: 'qualified',
          referrerUserId,
          referredUserId: userId,
          rewardAmount: referral.rewardDays ?? 28,
        },
      })

      logger.info('Referral qualified and reward job enqueued', {
        jobId: job.id,
        referralId,
        referrerUserId,
        referredUserId: userId,
      })
    },
  )
}
