import {
  decodeNotificationPayload,
  decodeTransaction,
  decodeRenewalInfo,
  NotificationType,
  NotificationSubtype,
  type DecodedNotificationPayload,
  type DecodedNotificationDataPayload,
  type JWSTransactionDecodedPayload,
  type JWSRenewalInfoDecodedPayload,
} from 'app-store-server-api';
import { Subscription, type ISubscription } from '../../models/Subscription.js';
import { ProcessedWebhookEvent } from '../../models/ProcessedWebhookEvent.js';
import logger from '../../utils/logger.js';

export type AppleNotificationHandlerResult =
  | { status: 'processed'; notificationType: string; subscriptionId?: string }
  | { status: 'duplicate'; notificationUUID: string }
  | { status: 'ignored'; reason: string; notificationType?: string }
  | { status: 'invalid'; reason: string };

export interface AppleNotificationDependencies {
  decodeNotification?: typeof decodeNotificationPayload;
  decodeTransaction?: typeof decodeTransaction;
  decodeRenewalInfo?: typeof decodeRenewalInfo;
}

/**
 * Deterministically maps an Apple notificationType (+ subtype) to a new
 * subscription state. Returns null when the notification type is a no-op
 * (summary events, consumption requests, etc.) so the caller can log+ack.
 */
export function deriveSubscriptionStateChange(
  notificationType: string,
  subtype: string | undefined,
  transaction: JWSTransactionDecodedPayload | undefined,
  _renewalInfo: JWSRenewalInfoDecodedPayload | undefined,
): Partial<ISubscription> | null {
  const updates: Partial<ISubscription> = {};

  switch (notificationType) {
    case NotificationType.Subscribed:
    case NotificationType.DidRenew: {
      updates.status = 'active';
      if (transaction?.expiresDate) {
        updates.expiryDate = new Date(transaction.expiresDate);
      }
      if (transaction?.purchaseDate) {
        updates.purchaseDate = new Date(transaction.purchaseDate);
      }
      updates.autoRenew = true;
      return updates;
    }

    case NotificationType.DidChangeRenewalStatus: {
      if (subtype === NotificationSubtype.AutoRenewDisabled) {
        updates.autoRenew = false;
        return updates;
      }
      if (subtype === NotificationSubtype.AutoRenewEnabled) {
        updates.autoRenew = true;
        return updates;
      }
      return null;
    }

    case NotificationType.DidFailToRenew: {
      updates.status = 'past_due';
      return updates;
    }

    case NotificationType.GracePeriodExpired:
    case NotificationType.Expired: {
      updates.status = 'expired';
      updates.autoRenew = false;
      return updates;
    }

    case NotificationType.Refund: {
      updates.status = 'refunded';
      updates.cancelledAt = new Date();
      updates.autoRenew = false;
      return updates;
    }

    case NotificationType.Revoke: {
      updates.status = 'revoked';
      updates.cancelledAt = new Date();
      updates.autoRenew = false;
      return updates;
    }

    default:
      return null;
  }
}

/**
 * Handle a signed Apple App Store Server Notification v2 payload. All
 * verification is performed via `decodeNotificationPayload` from
 * `app-store-server-api` which validates the JWS x5c chain against
 * Apple's root CA. Duplicates are rejected via `ProcessedWebhookEvent`.
 */
export async function handleAppleSignedNotification(
  signedPayload: string,
  deps: AppleNotificationDependencies = {},
): Promise<AppleNotificationHandlerResult> {
  if (typeof signedPayload !== 'string' || !signedPayload.trim()) {
    return { status: 'invalid', reason: 'signedPayload is required' };
  }

  const decodeNotification = deps.decodeNotification ?? decodeNotificationPayload;
  const decodeTx = deps.decodeTransaction ?? decodeTransaction;
  const decodeRenewal = deps.decodeRenewalInfo ?? decodeRenewalInfo;

  let notification: DecodedNotificationPayload;
  try {
    notification = await decodeNotification(signedPayload);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Signature verification failed';
    logger.warn('Apple notification signature verification failed', {
      error: message,
    });
    return { status: 'invalid', reason: message };
  }

  const { notificationType, subtype, notificationUUID } = notification;

  if (!notificationUUID) {
    return { status: 'invalid', reason: 'Notification missing notificationUUID' };
  }

  // Idempotency: if we've already processed this notificationUUID, ack and skip.
  const existing = await ProcessedWebhookEvent.findOne({
    provider: 'apple',
    eventId: notificationUUID,
  }).lean();
  if (existing) {
    logger.info('Ignoring duplicate Apple notification', {
      notificationUUID,
      notificationType,
    });
    return { status: 'duplicate', notificationUUID };
  }

  // Only data-bearing notifications can drive subscription state changes.
  // Summary payloads (RENEWAL_EXTENSION with SUMMARY, etc.) have no
  // signedTransactionInfo — we log + ack them.
  const dataPayload = (notification as DecodedNotificationDataPayload).data;

  let transaction: JWSTransactionDecodedPayload | undefined;
  let renewalInfo: JWSRenewalInfoDecodedPayload | undefined;

  if (dataPayload?.signedTransactionInfo) {
    try {
      transaction = await decodeTx(dataPayload.signedTransactionInfo);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Invalid signedTransactionInfo';
      logger.warn('Apple notification transaction decode failed', {
        error: message,
        notificationUUID,
      });
      return { status: 'invalid', reason: message };
    }
  }

  if (dataPayload?.signedRenewalInfo) {
    try {
      renewalInfo = await decodeRenewal(dataPayload.signedRenewalInfo);
    } catch (err) {
      // Renewal info is optional — log and continue.
      logger.warn('Apple notification renewal info decode failed', {
        error: err instanceof Error ? err.message : String(err),
        notificationUUID,
      });
    }
  }

  const updates = deriveSubscriptionStateChange(
    notificationType,
    subtype,
    transaction,
    renewalInfo,
  );

  // Record the notification as processed BEFORE applying state so retries
  // after a partial failure don't double-apply. Use a unique index to win
  // the race if Apple fires two parallel retries.
  try {
    await ProcessedWebhookEvent.create({
      provider: 'apple',
      eventId: notificationUUID,
      type: notificationType,
    });
  } catch (err) {
    // Unique-constraint violation = concurrent duplicate; treat as idempotent.
    const code = (err as { code?: number })?.code;
    if (code === 11000) {
      return { status: 'duplicate', notificationUUID };
    }
    throw err;
  }

  if (!updates) {
    logger.info('Ignoring unhandled Apple notification type', {
      notificationType,
      subtype,
      notificationUUID,
    });
    return { status: 'ignored', reason: 'unhandled notification type', notificationType };
  }

  const originalTransactionId =
    transaction?.originalTransactionId
    ?? renewalInfo?.originalTransactionId;

  if (!originalTransactionId) {
    logger.warn('Apple notification missing originalTransactionId', {
      notificationType,
      notificationUUID,
    });
    return { status: 'ignored', reason: 'missing originalTransactionId', notificationType };
  }

  // Lookup subscription by either the new field or the legacy provider field
  // so the existing records created by validateAppleTransaction are matched.
  const subscription = await Subscription.findOne({
    provider: 'apple',
    $or: [
      { originalTransactionId },
      { providerOriginalTransactionId: originalTransactionId },
    ],
  });

  if (!subscription) {
    logger.warn('Apple notification for unknown originalTransactionId', {
      originalTransactionId,
      notificationType,
      notificationUUID,
    });
    return { status: 'ignored', reason: 'unknown originalTransactionId', notificationType };
  }

  // Apply updates
  if (updates.status !== undefined) subscription.status = updates.status;
  if (updates.expiryDate) subscription.expiryDate = updates.expiryDate;
  if (updates.purchaseDate) subscription.purchaseDate = updates.purchaseDate;
  if (updates.autoRenew !== undefined) subscription.autoRenew = updates.autoRenew;
  if (updates.cancelledAt) subscription.cancelledAt = updates.cancelledAt;

  if (!subscription.originalTransactionId) {
    subscription.originalTransactionId = originalTransactionId;
  }
  subscription.lastValidatedAt = new Date();

  await subscription.save();

  logger.info('Applied Apple notification to subscription', {
    userId: subscription.userId.toString(),
    subscriptionId: subscription._id.toString(),
    notificationType,
    subtype,
    newStatus: subscription.status,
    autoRenew: subscription.autoRenew,
  });

  return {
    status: 'processed',
    notificationType,
    subscriptionId: subscription._id.toString(),
  };
}
