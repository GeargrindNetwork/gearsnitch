import { Subscription, type ISubscription } from '../../models/Subscription.js';
import logger from '../../utils/logger.js';
import {
  decodeTransaction,
  Environment,
  type JWSTransactionDecodedPayload,
} from 'app-store-server-api';

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

const APPLE_EXPECTED_BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? 'com.gearsnitch.app';

/**
 * Resolves the expected StoreKit environment (Production | Sandbox).
 * When `APPLE_STOREKIT_ENV` is unset we default to Production, but we also
 * honour the environment declared inside the verified JWS payload so that
 * Sandbox receipts remain usable in staging/QA builds.
 */
function getConfiguredAppleEnvironment(): Environment | null {
  const raw = process.env.APPLE_STOREKIT_ENV;
  if (!raw) return null;
  if (raw === Environment.Sandbox) return Environment.Sandbox;
  if (raw === Environment.Production) return Environment.Production;
  return null;
}

/**
 * Verifies an Apple StoreKit 2 JWS-signed transaction.
 *
 * Uses `app-store-server-api`'s `decodeTransaction`, which:
 *   - Parses the JWS x5c header cert chain
 *   - Validates the chain back to Apple's Root CA (G3) fingerprint
 *   - Verifies the JWS signature with the leaf cert's ES256 public key
 *   - Returns the strongly-typed `JWSTransactionDecodedPayload`
 *
 * Any failure (malformed JWS, broken cert chain, bad signature, expired
 * leaf cert, non-Apple root) throws — we surface these as a single
 * `APPLE_JWS_VERIFICATION_FAILED` error so the route layer maps cleanly
 * to a 400. Bundle-ID mismatches are treated the same way to prevent a
 * receipt from a different Apple app being replayed against GearSnitch.
 */
async function verifyAppleJws(jwsRepresentation: string): Promise<JWSTransactionDecodedPayload> {
  if (typeof jwsRepresentation !== 'string' || jwsRepresentation.length === 0) {
    throw new Error('APPLE_JWS_VERIFICATION_FAILED: empty jwsRepresentation');
  }

  const parts = jwsRepresentation.split('.');
  if (parts.length !== 3) {
    throw new Error('APPLE_JWS_VERIFICATION_FAILED: expected 3 JWS segments');
  }

  let verified: JWSTransactionDecodedPayload;
  try {
    verified = await decodeTransaction(jwsRepresentation);
  } catch (err) {
    logger.error('Apple JWS signature verification failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    throw new Error('APPLE_JWS_VERIFICATION_FAILED: signature or certificate chain invalid');
  }

  if (verified.bundleId !== APPLE_EXPECTED_BUNDLE_ID) {
    logger.error('Apple JWS bundle id mismatch', {
      expected: APPLE_EXPECTED_BUNDLE_ID,
      received: verified.bundleId,
    });
    throw new Error('APPLE_JWS_VERIFICATION_FAILED: bundle id mismatch');
  }

  const expectedEnv = getConfiguredAppleEnvironment();
  if (expectedEnv && verified.environment !== expectedEnv) {
    // Not fatal in sandbox builds — but we log so ops can spot misconfigurations.
    logger.warn('Apple JWS environment does not match configured APPLE_STOREKIT_ENV', {
      expected: expectedEnv,
      received: verified.environment,
    });
  }

  return verified;
}

/**
 * Validates an Apple StoreKit 2 JWS-signed transaction and upserts the
 * local Subscription record.
 */
export async function validateAppleTransaction(
  jwsRepresentation: string,
  userId: string,
): Promise<SubscriptionResult> {
  // ----- 1. Verify the JWS signature against Apple's Root CA (G3) -----
  const verified = await verifyAppleJws(jwsRepresentation);

  // Project the verified payload onto the internal shape consumed by the
  // rest of this function. The keys are identical to what the previous
  // unverified decode path produced, so downstream behaviour is byte-compatible.
  const payload: AppleTransactionPayload = {
    transactionId: verified.transactionId,
    originalTransactionId: verified.originalTransactionId,
    bundleId: verified.bundleId,
    productId: verified.productId,
    purchaseDate: verified.purchaseDate,
    expiresDate: verified.expiresDate,
    type: verified.type,
    environment: verified.environment,
  };

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
