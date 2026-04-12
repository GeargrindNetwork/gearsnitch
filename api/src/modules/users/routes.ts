import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { User } from '../../models/User.js';
import { Device } from '../../models/Device.js';
import { Gym } from '../../models/Gym.js';
import { Referral } from '../../models/Referral.js';
import { Session } from '../../models/Session.js';
import { StoreOrder } from '../../models/StoreOrder.js';
import { AuthService } from '../../services/AuthService.js';
import {
  PERMISSION_STATE_VALUES,
  normalizePermissionsState,
} from '../../utils/permissionsState.js';
import {
  getSubscriptionForUser,
  getSubscriptionPlanFromProductId,
  getSubscriptionTierFromProductId,
} from '../subscriptions/subscriptionService.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

const CM_PER_INCH = 2.54;
const KG_PER_POUND = 0.45359237;
const ACCOUNT_DELETION_GRACE_DAYS = 30;
const MAX_AVATAR_URL_LENGTH = 2_000_000;

const avatarValueSchema = z
  .string()
  .trim()
  .min(1)
  .max(MAX_AVATAR_URL_LENGTH)
  .refine(
    (value) =>
      value.startsWith('http://')
      || value.startsWith('https://')
      || /^data:image\/(?:jpeg|png|webp);base64,/.test(value),
    'Avatar must be an http(s) URL or a supported image data URL',
  );

const updateMeSchema = z.object({
  displayName: z.string().trim().min(1).max(120).optional(),
  avatarURL: z.string().trim().min(1).max(2048).optional(),
  preferences: z.record(z.string()).optional(),
  onboardingCompletedAt: z.string().datetime().optional(),
  permissionsState: z.object({
    bluetooth: z.enum(PERMISSION_STATE_VALUES).optional(),
    location: z.enum(PERMISSION_STATE_VALUES).optional(),
    backgroundLocation: z.enum(PERMISSION_STATE_VALUES).optional(),
    notifications: z.enum(PERMISSION_STATE_VALUES).optional(),
    healthKit: z.enum(PERMISSION_STATE_VALUES).optional(),
  }).optional(),
});

const updateAvatarSchema = z.object({
  avatarURL: avatarValueSchema.nullable(),
});

const updateProfileSchema = z.object({
  firstName: z.string().trim().max(100),
  lastName: z.string().trim().max(100),
  dateOfBirth: z.string().datetime(),
  heightInches: z.number().finite().positive().max(120),
  weightLbs: z.number().finite().positive().max(2000),
});

// GET /users/me
router.get('/me', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = (req.user as JwtPayload).sub;
    const profile = await buildProfileResponse(userId);

    if (!profile) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    successResponse(res, profile);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to get current user',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// POST /users/me/export
router.post('/me/export', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = (req.user as JwtPayload).sub;
    const exportPayload = await buildDataExport(userId);

    if (!exportPayload) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    successResponse(res, exportPayload);
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to export user data',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// PATCH /users/me
router.patch(
  '/me',
  isAuthenticated,
  validateBody(updateMeSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = (req.user as JwtPayload).sub;
      const body = req.body as z.infer<typeof updateMeSchema>;
      const user = await User.findById(userId);

      if (!user) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
        return;
      }

      if (body.displayName !== undefined) {
        user.displayName = body.displayName;
      }

      if (body.avatarURL !== undefined) {
        user.photoUrl = body.avatarURL;
      }

      if (body.onboardingCompletedAt !== undefined) {
        user.onboardingCompletedAt = new Date(body.onboardingCompletedAt);
      }

      if (body.permissionsState !== undefined) {
        const existingPermissions = normalizePermissionsState(user.permissionsState);
        user.permissionsState = {
          ...existingPermissions,
          ...body.permissionsState,
        };
      }

      if (body.preferences !== undefined) {
        const existingPreferences = user.preferences ?? {
          pushEnabled: false,
          panicAlertsEnabled: false,
          disconnectAlertsEnabled: false,
          custom: {},
        };

        user.preferences = {
          pushEnabled: existingPreferences.pushEnabled ?? false,
          panicAlertsEnabled: existingPreferences.panicAlertsEnabled ?? false,
          disconnectAlertsEnabled:
            existingPreferences.disconnectAlertsEnabled ?? false,
          custom: {
            ...(existingPreferences.custom ?? {}),
            ...body.preferences,
          },
        };
      }

      await user.save();
      successResponse(res, buildUserResponse(user));
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update current user',
        err instanceof Error ? err.message : String(err),
      );
    }
  },
);

// PATCH /users/me/avatar
router.patch(
  '/me/avatar',
  isAuthenticated,
  validateBody(updateAvatarSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = (req.user as JwtPayload).sub;
      const body = req.body as z.infer<typeof updateAvatarSchema>;
      const user = await User.findById(userId);

      if (!user) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
        return;
      }

      user.photoUrl = body.avatarURL ?? undefined;
      await user.save();

      const profile = await buildProfileResponse(userId);
      if (!profile) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
        return;
      }

      successResponse(res, profile);
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update profile photo',
        err instanceof Error ? err.message : String(err),
      );
    }
  },
);

// PATCH /users/me/profile
router.patch(
  '/me/profile',
  isAuthenticated,
  validateBody(updateProfileSchema),
  async (req: Request, res: Response) => {
    try {
      const userId = (req.user as JwtPayload).sub;
      const body = req.body as z.infer<typeof updateProfileSchema>;
      const user = await User.findById(userId);

      if (!user) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
        return;
      }

      user.firstName = body.firstName || undefined;
      user.lastName = body.lastName || undefined;
      user.dateOfBirth = new Date(body.dateOfBirth);
      user.heightCm = inchesToCm(body.heightInches);
      user.weightKg = poundsToKg(body.weightLbs);

      const derivedDisplayName = [body.firstName, body.lastName]
        .filter((part) => part.length > 0)
        .join(' ')
        .trim();
      const fallbackDisplayName = user.email.split('@')[0];

      if (
        derivedDisplayName
        && (!user.displayName || user.displayName === fallbackDisplayName)
      ) {
        user.displayName = derivedDisplayName;
      }

      await user.save();

      const profile = await buildProfileResponse(userId);
      if (!profile) {
        errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
        return;
      }

      successResponse(res, profile);
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to update user profile',
        err instanceof Error ? err.message : String(err),
      );
    }
  },
);

// DELETE /users/me
router.delete('/me', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const userId = (req.user as JwtPayload).sub;
    const user = await User.findById(userId);

    if (!user) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    const deletionRequestedAt = new Date();
    const deletionScheduledFor = new Date(
      deletionRequestedAt.getTime()
      + ACCOUNT_DELETION_GRACE_DAYS * 24 * 60 * 60 * 1000,
    );

    user.status = 'deletion_requested';
    user.deletionRequestedAt = deletionRequestedAt;
    user.deletionScheduledFor = deletionScheduledFor;
    user.deletedAt = null;
    await user.save();

    await AuthService.logoutAll(userId);

    successResponse(res, {
      deletionRequestedAt,
      deletionScheduledFor,
      gracePeriodDays: ACCOUNT_DELETION_GRACE_DAYS,
    });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to request account deletion',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /users/:id
router.get('/:id', isAuthenticated, (_req, res) => {
  successResponse(res, { message: 'Get user by ID — not yet implemented' }, 501);
});

function inchesToCm(inches: number): number {
  return roundToSingleDecimal(inches * CM_PER_INCH);
}

function poundsToKg(pounds: number): number {
  return roundToSingleDecimal(pounds * KG_PER_POUND);
}

function cmToInches(cm: number | null | undefined): number | null {
  if (!cm || cm <= 0) {
    return null;
  }
  return roundToSingleDecimal(cm / CM_PER_INCH);
}

function kgToPounds(kg: number | null | undefined): number | null {
  if (!kg || kg <= 0) {
    return null;
  }
  return roundToSingleDecimal(kg / KG_PER_POUND);
}

function roundToSingleDecimal(value: number): number {
  return Math.round(value * 10) / 10;
}

function toIsoString(value: Date | null | undefined): string | null {
  return value ? value.toISOString() : null;
}

function formatSubscriptionPlan(productId: string | null | undefined): string | null {
  return getSubscriptionPlanFromProductId(productId);
}

function buildSubscriptionSummary(
  subscription: {
    status: string;
    productId: string;
    expiryDate: Date;
  } | null,
) {
  if (!subscription) {
    return null;
  }

  return {
    status: subscription.status,
    plan: formatSubscriptionPlan(subscription.productId),
    expiresAt: subscription.expiryDate.toISOString(),
  };
}

function serializeGymSummary(gym: {
  _id: { toString(): string };
  name: string;
  isDefault: boolean;
  radiusMeters: number;
  location: {
    coordinates: [number, number];
  };
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    _id: gym._id.toString(),
    name: gym.name,
    isDefault: gym.isDefault,
    radiusMeters: gym.radiusMeters,
    location: {
      longitude: gym.location.coordinates[0],
      latitude: gym.location.coordinates[1],
    },
    createdAt: gym.createdAt.toISOString(),
    updatedAt: gym.updatedAt.toISOString(),
  };
}

function buildUserResponse(user: {
  _id: { toString(): string };
  email: string;
  displayName: string;
  photoUrl?: string;
  referralCode?: string | null;
  roles: string[];
  status: string;
  defaultGymId?: { toString(): string } | null;
  onboardingCompletedAt?: Date | null;
  permissionsState?: unknown;
  preferences?: unknown;
}) {
  return {
    _id: user._id.toString(),
    email: user.email,
    displayName: user.displayName,
    avatarURL: user.photoUrl,
    referralCode: user.referralCode ?? null,
    role: user.roles[0] ?? 'user',
    status: user.status,
    defaultGymId: user.defaultGymId ? user.defaultGymId.toString() : null,
    onboardingCompletedAt: toIsoString(user.onboardingCompletedAt),
    permissionsState: normalizePermissionsState(user.permissionsState),
    preferences: user.preferences,
  };
}

async function buildProfileResponse(userId: string) {
  const user = await User.findById(userId).lean();
  if (!user) {
    return null;
  }

  const [referral, subscription, orderCount, devices, gyms] = await Promise.all([
    Referral.findOne({ referrerUserId: user._id }).sort({ createdAt: -1 }).lean(),
    getSubscriptionForUser(userId),
    StoreOrder.countDocuments({
      userId: user._id,
      status: { $ne: 'cancelled' },
    }),
    Device.find({ userId: user._id }).sort({ isFavorite: -1, updatedAt: -1, createdAt: -1 }).lean(),
    Gym.find({ userId: user._id }).sort({ isDefault: -1, createdAt: -1 }).lean(),
  ]);

  const normalizedPermissions = normalizePermissionsState(user.permissionsState);
  const defaultGym = gyms.find((gym) => gym.isDefault);

  return {
    _id: user._id.toString(),
    email: user.email,
    displayName: user.displayName,
    firstName: user.firstName ?? null,
    lastName: user.lastName ?? null,
    avatarURL: user.photoUrl ?? null,
    role: user.roles[0] ?? 'user',
    status: user.status,
    referralCode: user.referralCode ?? referral?.referralCode ?? null,
    subscriptionTier:
      subscription && ['active', 'grace_period'].includes(subscription.status)
        ? getSubscriptionTierFromProductId(subscription.productId)
        : 'free',
    defaultGymId: user.defaultGymId ? String(user.defaultGymId) : null,
    onboardingCompletedAt: toIsoString(user.onboardingCompletedAt),
    permissionsState: normalizedPermissions,
    preferences: user.preferences,
    linkedAccounts: user.authProviders,
    subscription: buildSubscriptionSummary(subscription),
    devices: devices.map((device) => ({
      _id: String(device._id),
      deviceName: device.name,
      nickname: device.nickname ?? null,
      platform: device.type,
      bluetoothIdentifier: device.identifier,
      status: device.status,
      isFavorite: device.isFavorite === true,
      isMonitoring: device.monitoringEnabled === true,
      lastSeen: toIsoString(device.lastSeenAt),
      createdAt: toIsoString(device.createdAt),
    })),
    pinnedDeviceId:
      devices.find((device) => device.isFavorite === true)?._id?.toString() ?? null,
    gyms: gyms.map(serializeGymSummary),
    defaultGym:
      defaultGym?.location?.coordinates?.length === 2
        ? serializeGymSummary(defaultGym)
        : null,
    onboarding: {
      hasAddedGym: gyms.length > 0,
      hasPairedDevice: devices.length > 0,
      bluetoothGranted: normalizedPermissions.bluetooth === 'granted',
      locationGranted: normalizedPermissions.location === 'granted',
      backgroundLocationGranted: normalizedPermissions.backgroundLocation === 'granted',
      notificationsGranted: normalizedPermissions.notifications === 'granted',
      healthKitGranted: normalizedPermissions.healthKit === 'granted',
    },
    createdAt: user.createdAt.toISOString(),
    dateOfBirth: user.dateOfBirth ? user.dateOfBirth.toISOString() : null,
    heightInches: cmToInches(user.heightCm),
    weightLbs: kgToPounds(user.weightKg),
    orderCount,
  };
}

async function buildDataExport(userId: string) {
  const user = await User.findById(userId).lean();
  if (!user) {
    return null;
  }

  const [subscription, referrals, orders, devices, sessions, gyms] = await Promise.all([
    getSubscriptionForUser(userId),
    Referral.find({ referrerUserId: user._id }).sort({ createdAt: -1 }).lean(),
    StoreOrder.find({ userId: user._id }).sort({ createdAt: -1 }).lean(),
    Device.find({ userId: user._id }).sort({ createdAt: -1 }).lean(),
    Session.find({ userId: user._id }).sort({ createdAt: -1 }).lean(),
    Gym.find({ userId: user._id }).sort({ isDefault: -1, createdAt: -1 }).lean(),
  ]);

  const latestReferralCode = referrals[0]?.referralCode ?? null;
  const subscriptionTier =
    subscription && ['active', 'grace_period'].includes(subscription.status)
      ? getSubscriptionTierFromProductId(subscription.productId)
      : 'free';
  const normalizedPermissions = normalizePermissionsState(user.permissionsState);

  return {
    exportVersion: 1,
    exportedAt: new Date().toISOString(),
    account: {
      _id: String(user._id),
      email: user.email,
      displayName: user.displayName,
      avatarURL: user.photoUrl ?? null,
      firstName: user.firstName ?? null,
      lastName: user.lastName ?? null,
      status: user.status,
      roles: user.roles,
      linkedAccounts: user.authProviders,
      createdAt: user.createdAt.toISOString(),
      updatedAt: user.updatedAt.toISOString(),
      dateOfBirth: toIsoString(user.dateOfBirth),
      biologicalSex: user.biologicalSex ?? null,
      bloodType: user.bloodType ?? null,
      heightCm: user.heightCm ?? null,
      weightKg: user.weightKg ?? null,
      defaultGymId: user.defaultGymId ? String(user.defaultGymId) : null,
      onboardingCompletedAt: toIsoString(user.onboardingCompletedAt),
      permissionsState: normalizedPermissions,
      preferences: user.preferences,
    },
    summary: {
      subscriptionTier,
      referralCode: user.referralCode ?? latestReferralCode,
      orderCount: orders.length,
      deviceCount: devices.length,
      gymCount: gyms.length,
      sessionCount: sessions.length,
    },
    subscription: subscription
      ? {
          provider: subscription.provider,
          productId: subscription.productId,
          plan: formatSubscriptionPlan(subscription.productId),
          status: subscription.status,
          purchaseDate: subscription.purchaseDate.toISOString(),
          expiryDate: subscription.expiryDate.toISOString(),
          extensionDays: subscription.extensionDays,
          lastValidatedAt: subscription.lastValidatedAt.toISOString(),
        }
      : null,
    referrals: referrals.map((referral) => ({
      _id: String(referral._id),
      referralCode: referral.referralCode,
      status: referral.status,
      rewardDays: referral.rewardDays,
      referredUserId: referral.referredUserId ? String(referral.referredUserId) : null,
      qualifiedAt: toIsoString(referral.qualifiedAt),
      rewardedAt: toIsoString(referral.rewardedAt),
      reason: referral.reason ?? null,
      createdAt: referral.createdAt.toISOString(),
      updatedAt: referral.updatedAt.toISOString(),
    })),
    orders: orders.map((order) => ({
      _id: String(order._id),
      orderNumber: order.orderNumber,
      paymentIntentId: order.paymentIntentId ?? null,
      status: order.status,
      subtotal: order.subtotal,
      tax: order.tax,
      shipping: order.shipping,
      total: order.total,
      currency: order.currency,
      complianceAccepted: order.complianceAccepted ?? null,
      shippingAddress: order.shippingAddress,
      items: order.items.map((item) => ({
        productId: String(item.productId),
        sku: item.sku,
        name: item.name,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        lineTotal: item.lineTotal,
      })),
      createdAt: order.createdAt.toISOString(),
      updatedAt: order.updatedAt.toISOString(),
    })),
    devices: devices.map((device) => ({
      _id: String(device._id),
      name: device.name,
      nickname: device.nickname ?? null,
      type: device.type,
      identifier: device.identifier,
      hardwareModel: device.hardwareModel ?? null,
      firmwareVersion: device.firmwareVersion ?? null,
      status: device.status,
      isFavorite: device.isFavorite === true,
      monitoringEnabled: device.monitoringEnabled,
      lastSeenAt: toIsoString(device.lastSeenAt),
      lastSeenLocation: device.lastSeenLocation ?? null,
      lastSignalStrength: device.lastSignalStrength ?? null,
      createdAt: device.createdAt.toISOString(),
      updatedAt: device.updatedAt.toISOString(),
    })),
    gyms: gyms.map(serializeGymSummary),
    sessions: sessions.map((session) => ({
      _id: String(session._id),
      deviceName: session.deviceName,
      platform: session.platform,
      ipAddress: session.ipAddress,
      userAgent: session.userAgent,
      expiresAt: session.expiresAt.toISOString(),
      revokedAt: toIsoString(session.revokedAt),
      createdAt: session.createdAt.toISOString(),
    })),
  };
}

export default router;
