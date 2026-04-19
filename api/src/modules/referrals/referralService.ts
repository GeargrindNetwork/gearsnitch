import { Types } from 'mongoose';
import { Referral, type IReferral } from '../../models/Referral.js';
import { Subscription, type ISubscription } from '../../models/Subscription.js';
import type { IUser } from '../../models/User.js';
import logger from '../../utils/logger.js';

export const REFERRAL_REWARD_DAYS = 28;

const REWARD_ELIGIBLE_SUBSCRIPTION_STATUSES: ReadonlyArray<
  ISubscription['status']
> = ['active', 'grace_period'];

const REFERRAL_PENDING_SUBSCRIPTION_REASON = 'Awaiting qualifying subscription';
const REFERRAL_PENDING_REFERRER_PLAN_REASON =
  'Referrer must have an active paid subscription to earn bonus days';

function addDays(baseDate: Date, days: number): Date {
  return new Date(baseDate.getTime() + days * 24 * 60 * 60 * 1000);
}

function toObjectId(value: string | Types.ObjectId): Types.ObjectId {
  return typeof value === 'string' ? new Types.ObjectId(value) : value;
}

function getRewardDays(referral: Pick<IReferral, 'rewardDays'>): number {
  return typeof referral.rewardDays === 'number' && referral.rewardDays > 0
    ? referral.rewardDays
    : REFERRAL_REWARD_DAYS;
}

async function getLatestRewardEligibleSubscription(
  userId: Types.ObjectId,
): Promise<ISubscription | null> {
  return Subscription.findOne({
    userId,
    status: { $in: REWARD_ELIGIBLE_SUBSCRIPTION_STATUSES },
  })
    .sort({ expiryDate: -1 })
    .exec();
}

async function rewardQualifiedReferral(
  referral: IReferral,
  now: Date,
): Promise<void> {
  if (referral.status === 'rewarded') {
    return;
  }

  const referrerSubscription = await getLatestRewardEligibleSubscription(
    referral.referrerUserId,
  );

  if (!referrerSubscription) {
    if (referral.reason !== REFERRAL_PENDING_REFERRER_PLAN_REASON) {
      referral.reason = REFERRAL_PENDING_REFERRER_PLAN_REASON;
      await referral.save();
    }
    return;
  }

  const rewardDays = getRewardDays(referral);
  const baseExpiry =
    referrerSubscription.expiryDate > now ? referrerSubscription.expiryDate : now;

  referrerSubscription.expiryDate = addDays(baseExpiry, rewardDays);
  referrerSubscription.extensionDays =
    Math.max(referrerSubscription.extensionDays ?? 0, 0) + rewardDays;
  referrerSubscription.lastValidatedAt = now;
  referrerSubscription.status = 'active';

  referral.status = 'rewarded';
  referral.qualifiedAt ??= now;
  referral.rewardedAt = now;
  referral.reason = undefined;

  await Promise.all([referrerSubscription.save(), referral.save()]);
}

async function qualifyReferral(referral: IReferral, now: Date): Promise<void> {
  if (!referral.referredUserId) {
    return;
  }

  const referredSubscription = await getLatestRewardEligibleSubscription(
    referral.referredUserId,
  );

  if (!referredSubscription) {
    if (referral.reason !== REFERRAL_PENDING_SUBSCRIPTION_REASON) {
      referral.reason = REFERRAL_PENDING_SUBSCRIPTION_REASON;
      await referral.save();
    }
    return;
  }

  if (referral.status === 'pending') {
    referral.status = 'qualified';
    referral.qualifiedAt ??= now;
    referral.reason = undefined;
    await referral.save();
  }

  await rewardQualifiedReferral(referral, now);
}

export async function processReferralQualificationForReferredUser(
  referredUserId: string | Types.ObjectId,
): Promise<void> {
  const referralUserObjectId = toObjectId(referredUserId);
  const referrals = await Referral.find({
    referredUserId: referralUserObjectId,
    status: 'pending',
  })
    .sort({ createdAt: 1 })
    .exec();

  const now = new Date();
  for (const referral of referrals) {
    await qualifyReferral(referral, now);
  }
}

/**
 * Record an attribution from `referee` to `referrer`. Creates a pending
 * Referral row if none exists yet for the pair, then runs the qualification
 * pipeline so already-paid referees get rewarded immediately.
 *
 * Idempotent: if a Referral row already exists for the pair we return it
 * without creating a duplicate. The User.referredBy write is owned by the
 * caller (the /referrals/claim route) — this helper only creates the
 * Referral ledger entry.
 */
export async function recordAttribution(
  referrer: Pick<IUser, '_id'>,
  referee: Pick<IUser, '_id'>,
  referralCode: string,
): Promise<IReferral> {
  if (String(referrer._id) === String(referee._id)) {
    throw new Error('Self-referral is not allowed');
  }

  const existing = await Referral.findOne({
    referrerUserId: referrer._id,
    referredUserId: referee._id,
  });

  if (existing) {
    logger.info('recordAttribution: Referral row already exists', {
      referralId: String(existing._id),
      referrerId: String(referrer._id),
      refereeId: String(referee._id),
    });
    return existing;
  }

  const referredSubscription = await getLatestRewardEligibleSubscription(
    referee._id,
  );

  const referral = await Referral.create({
    referrerUserId: referrer._id,
    referredUserId: referee._id,
    referralCode,
    status: 'pending',
    rewardDays: REFERRAL_REWARD_DAYS,
    reason: referredSubscription ? undefined : 'Awaiting qualifying subscription',
  });

  if (referredSubscription) {
    await processReferralQualificationForReferredUser(referee._id);
  }

  return referral;
}

export async function processOutstandingReferralRewardsForReferrer(
  referrerUserId: string | Types.ObjectId,
): Promise<void> {
  const referrerUserObjectId = toObjectId(referrerUserId);
  const referrals = await Referral.find({
    referrerUserId: referrerUserObjectId,
    status: 'qualified',
  })
    .sort({ qualifiedAt: 1, createdAt: 1 })
    .exec();

  const now = new Date();
  for (const referral of referrals) {
    await rewardQualifiedReferral(referral, now);
  }
}
