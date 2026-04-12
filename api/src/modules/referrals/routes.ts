import { randomBytes } from 'node:crypto';
import { Router, type Request } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { Referral } from '../../models/Referral.js';
import { Subscription } from '../../models/Subscription.js';
import { User } from '../../models/User.js';
import { errorResponse, successResponse } from '../../utils/response.js';

const router = Router();

const redeemSchema = z.object({
  referralCode: z.string().trim().min(4).max(32),
});

const REFERRAL_REWARD_DAYS = 90;
const REFERRAL_BASE_URL = 'https://gearsnitch.com/ref';

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function buildReferralUrl(referralCode: string): string {
  return `${REFERRAL_BASE_URL}/${referralCode}`;
}

async function generateUniqueReferralCode(): Promise<string> {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const candidate = randomBytes(4).toString('hex').toUpperCase();
    const exists = await User.exists({ referralCode: candidate });
    if (!exists) {
      return candidate;
    }
  }

  throw new Error('Failed to generate a unique referral code');
}

async function ensureReferralCode(userId: string): Promise<string> {
  const user = await User.findById(userId);
  if (!user) {
    throw new Error('User not found');
  }

  if (user.referralCode) {
    return user.referralCode;
  }

  const referralCode = await generateUniqueReferralCode();
  user.referralCode = referralCode;
  await user.save();
  return referralCode;
}

function mapReferralHistoryStatus(status: string): 'pending' | 'completed' | 'expired' {
  if (status === 'rewarded' || status === 'qualified') {
    return 'completed';
  }

  if (status === 'rejected') {
    return 'expired';
  }

  return 'pending';
}

async function buildReferralPayload(userId: string) {
  const referralCode = await ensureReferralCode(userId);
  const userObjectId = new Types.ObjectId(userId);

  const [history, referrerSubscription] = await Promise.all([
    Referral.find({
      referrerUserId: userObjectId,
      referredUserId: { $ne: null },
    })
      .sort({ createdAt: -1 })
      .lean(),
    Subscription.findOne({ userId: userObjectId }).sort({ expiryDate: -1 }).lean(),
  ]);

  const referredIds = history
    .map((item) => item.referredUserId)
    .filter((value): value is Types.ObjectId => value instanceof Types.ObjectId);

  const referredUsers = referredIds.length
    ? await User.find({ _id: { $in: referredIds } }, { email: 1 }).lean()
    : [];
  const referredEmailById = new Map(
    referredUsers.map((user) => [String(user._id), user.email]),
  );

  const activeReferrals = history.filter((item) =>
    ['qualified', 'rewarded'].includes(item.status),
  ).length;
  const extensionDaysEarned = history
    .filter((item) => item.status === 'rewarded')
    .reduce((total, item) => total + (item.rewardDays || REFERRAL_REWARD_DAYS), 0);

  return {
    referralCode,
    referralURL: buildReferralUrl(referralCode),
    totalReferrals: history.length,
    activeReferrals,
    extensionDaysEarned:
      Math.max(extensionDaysEarned, referrerSubscription?.extensionDays ?? 0),
    history: history.map((item) => ({
      _id: String(item._id),
      referredEmail: item.referredUserId
        ? referredEmailById.get(String(item.referredUserId)) ?? null
        : null,
      status: mapReferralHistoryStatus(item.status),
      createdAt: item.createdAt,
    })),
  };
}

// GET /referrals/me
router.get('/me', isAuthenticated, async (req, res) => {
  try {
    const payload = await buildReferralPayload(getUserId(req));
    successResponse(res, payload);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load referral data',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /referrals/qr
router.get('/qr', isAuthenticated, async (req, res) => {
  try {
    const referralCode = await ensureReferralCode(getUserId(req));
    successResponse(res, {
      referralCode,
      referralURL: buildReferralUrl(referralCode),
      qrPayload: buildReferralUrl(referralCode),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to build referral QR payload',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /referrals
router.get('/', isAuthenticated, async (req, res) => {
  try {
    const payload = await buildReferralPayload(getUserId(req));
    successResponse(res, payload.history);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list referrals',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /referrals/generate
router.post('/generate', isAuthenticated, async (req, res) => {
  try {
    const referralCode = await ensureReferralCode(getUserId(req));
    successResponse(res, {
      referralCode,
      referralURL: buildReferralUrl(referralCode),
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to generate referral code',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /referrals/redeem
router.post('/redeem', isAuthenticated, async (req, res) => {
  try {
    const parsed = redeemSchema.safeParse(req.body);
    if (!parsed.success) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'Validation failed',
        parsed.error.flatten().fieldErrors,
      );
      return;
    }

    const userId = getUserId(req);
    const normalizedCode = parsed.data.referralCode.toUpperCase();
    const currentUser = await User.findById(userId);
    if (!currentUser) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    const referrer = await User.findOne({ referralCode: normalizedCode });
    if (!referrer) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Referral code not found');
      return;
    }

    if (String(referrer._id) === userId) {
      errorResponse(res, StatusCodes.CONFLICT, 'You cannot redeem your own referral code');
      return;
    }

    const existingReferral = await Referral.findOne({
      referredUserId: currentUser._id,
      referrerUserId: referrer._id,
    });

    if (existingReferral) {
      successResponse(res, {
        referralId: String(existingReferral._id),
        status: existingReferral.status,
      });
      return;
    }

    const now = new Date();
    const referredSubscription = await Subscription.findOne({
      userId: currentUser._id,
      status: { $in: ['active', 'grace_period'] },
    }).sort({ expiryDate: -1 });

    const referral = await Referral.create({
      referrerUserId: referrer._id,
      referredUserId: currentUser._id,
      referralCode: normalizedCode,
      status: referredSubscription ? 'qualified' : 'pending',
      rewardDays: REFERRAL_REWARD_DAYS,
      qualifiedAt: referredSubscription ? now : undefined,
      reason: referredSubscription ? undefined : 'Awaiting qualifying subscription',
    });

    successResponse(
      res,
      {
        referralId: String(referral._id),
        status: referral.status,
      },
      StatusCodes.CREATED,
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to redeem referral code',
      err instanceof Error ? err.message : String(err),
    );
  }
});

export default router;
