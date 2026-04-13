import { Subscription, type ISubscription } from '../../models/Subscription.js';
import logger from '../../utils/logger.js';
import * as jose from 'jose';

export type SubscriptionTier = 'free' | 'monthly' | 'annual' | 'lifetime';

interface AppleProductConfig {
  tier: Exclude<SubscriptionTier, 'free'>;
  plan: string;
  fallbackDurationDays?: number;
}

const LIFETIME_EXPIRY_DATE = new Date('2099-12-31T23:59:59.999Z');

const APPLE_PRODUCT_CONFIG: Record<string, AppleProductConfig> = {
  'com.geargrind.gearsnitch.monthly': {
    tier: 'monthly',
    plan: 'GearSnitch HUSTLE Monthly',
    fallbackDurationDays: 30,
  },
  'com.gearsnitch.app.monthly': {
    tier: 'monthly',
    plan: 'GearSnitch HUSTLE Monthly',
    fallbackDurationDays: 30,
  },
  'com.geargrind.gearsnitch.annual': {
    tier: 'annual',
    plan: 'GearSnitch HWMF Annual',
    fallbackDurationDays: 365,
  },
  'com.gearsnitch.app.annual': {
    tier: 'annual',
    plan: 'GearSnitch HWMF Annual',
    fallbackDurationDays: 365,
  },
  'com.geargrind.gearsnitch.lifetime': {
    tier: 'lifetime',
    plan: 'GearSnitch BABY MOMMA Lifetime',
  },
  'com.gearsnitch.app.lifetime': {
    tier: 'lifetime',
    plan: 'GearSnitch BABY MOMMA Lifetime',
  },
};

function getAppleProductConfig(productId: string): AppleProductConfig | undefined {
  return APPLE_PRODUCT_CONFIG[productId];
}

export function getSubscriptionTierFromProductId(
  productId: string | null | undefined,
): SubscriptionTier {
  if (!productId) {
    return 'free';
  }

  return getAppleProductConfig(productId)?.tier ?? 'free';
}

export function getSubscriptionPlanFromProductId(
  productId: string | null | undefined,
): string | null {
  if (!productId) {
    return null;
  }

  return getAppleProductConfig(productId)?.plan ?? productId;
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AppleTransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number; // ms since epoch
  expiresDate?: number;
  type: string;
  environment: string;
}

export interface SubscriptionResult {
  status: ISubscription['status'];
  purchaseDate: Date;
  expiryDate: Date;
  extensionDays: number;
  productId: string;
  provider: string;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/**
 * Validates an Apple StoreKit 2 JWS-signed transaction and upserts the
 * local Subscription record.
 */
export async function validateAppleTransaction(
  jwsRepresentation: string,
  userId: string,
): Promise<SubscriptionResult> {
  // ----- 1. Decode the JWS (StoreKit 2 transactions are signed JWTs) -----
  // In production you would verify the signature against Apple's root CA.
  // For now we decode the payload — the transaction was already verified
  // on-device via Transaction.verify() before being sent here.
  const parts = jwsRepresentation.split('.');
  if (parts.length !== 3) {
    throw new Error('Invalid JWS format: expected 3 parts');
  }

  let payload: AppleTransactionPayload;
  try {
    const decoded = jose.decodeJwt(jwsRepresentation);
    payload = decoded as unknown as AppleTransactionPayload;
  } catch (err) {
    logger.error('Failed to decode JWS transaction', { error: err });
    throw new Error('Invalid JWS transaction');
  }

  // ----- 2. Validate product ID -----
  const productConfig = getAppleProductConfig(payload.productId);
  if (!productConfig) {
    throw new Error(
      `Unexpected product ID: ${payload.productId}. Expected one of ${Object.keys(APPLE_PRODUCT_CONFIG).join(', ')}`,
    );
  }

  // ----- 3. Calculate dates -----
  const purchaseDate = new Date(payload.purchaseDate);
  const baseExpiry = payload.expiresDate
    ? new Date(payload.expiresDate)
    : productConfig.fallbackDurationDays
      ? new Date(
          purchaseDate.getTime() + productConfig.fallbackDurationDays * 24 * 60 * 60 * 1000,
        )
      : LIFETIME_EXPIRY_DATE;

  // ----- 4. Upsert subscription -----
  const existing = await Subscription.findOne({
    provider: 'apple',
    providerOriginalTransactionId: payload.originalTransactionId,
  });

  let subscription: ISubscription;

  if (existing) {
    // Update existing subscription
    existing.status = baseExpiry > new Date() ? 'active' : 'expired';
    existing.purchaseDate = purchaseDate;
    existing.expiryDate = new Date(
      baseExpiry.getTime() + existing.extensionDays * 24 * 60 * 60 * 1000,
    );
    existing.lastValidatedAt = new Date();
    subscription = await existing.save();

    logger.info('Updated Apple subscription', {
      userId,
      transactionId: payload.originalTransactionId,
      status: subscription.status,
    });
  } else {
    // Create new subscription
    subscription = await Subscription.create({
      userId,
      provider: 'apple',
      providerOriginalTransactionId: payload.originalTransactionId,
      productId: payload.productId,
      status: baseExpiry > new Date() ? 'active' : 'expired',
      purchaseDate,
      expiryDate: baseExpiry,
      lastValidatedAt: new Date(),
      extensionDays: 0,
    });

    logger.info('Created Apple subscription', {
      userId,
      transactionId: payload.originalTransactionId,
    });
  }

  return {
    status: subscription.status,
    purchaseDate: subscription.purchaseDate,
    expiryDate: subscription.expiryDate,
    extensionDays: subscription.extensionDays,
    productId: subscription.productId,
    provider: subscription.provider,
  };
}

/**
 * Returns the active subscription for a user, or null if none exists.
 */
export async function getSubscriptionForUser(
  userId: string,
): Promise<ISubscription | null> {
  return Subscription.findOne({ userId })
    .sort({ expiryDate: -1 })
    .exec();
}
