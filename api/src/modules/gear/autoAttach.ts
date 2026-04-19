import { Types } from 'mongoose';
import { User } from '../../models/User.js';
import { GearComponent, logGearUsage, type IGearComponent } from '../../models/GearComponent.js';
import { EventLog } from '../../models/EventLog.js';

/**
 * Look up the user's default GearComponent for a given HKWorkoutActivityType.
 * Returns null when the user has no default configured, the reference is
 * stale (gear deleted / not owned), or the gear has been retired.
 */
export async function resolveDefaultGear(
  userId: Types.ObjectId,
  activityType: string | null | undefined,
): Promise<IGearComponent | null> {
  if (!activityType) {
    return null;
  }

  const user = await User.findById(userId).select('preferences').lean();
  const map = (user?.preferences?.defaultGearByActivity ?? {}) as Record<string, unknown>;
  const raw = map[activityType];
  if (!raw) {
    return null;
  }

  const id = typeof raw === 'string' ? raw : (raw as { toString?: () => string })?.toString?.();
  if (!id || !Types.ObjectId.isValid(id)) {
    return null;
  }

  const gear = await GearComponent.findOne({
    _id: new Types.ObjectId(id),
    userId,
    retiredAt: null,
  });

  return gear;
}

/**
 * Emit an AutoGearAssigned EventLog record. Non-fatal: failures are
 * logged by the caller but never propagated — the gear attachment must
 * succeed even if observability insertion fails.
 *
 * We piggyback on the `profile_updated` event type to stay within the
 * existing EVENT_TYPES enum without broadening the schema in this PR;
 * the `metadata.kind === 'auto_gear_assigned'` discriminator makes the
 * record addressable for downstream analytics.
 */
export async function logAutoGearAssigned(params: {
  userId: Types.ObjectId;
  gearId: Types.ObjectId;
  activityType: string;
  workoutId?: Types.ObjectId;
  runId?: Types.ObjectId;
}): Promise<void> {
  try {
    await EventLog.create({
      userId: params.userId,
      eventType: 'profile_updated',
      source: 'system',
      timestamp: new Date(),
      metadata: {
        kind: 'auto_gear_assigned',
        gearId: String(params.gearId),
        activityType: params.activityType,
        workoutId: params.workoutId ? String(params.workoutId) : undefined,
        runId: params.runId ? String(params.runId) : undefined,
      },
    });
  } catch {
    // swallow — observability only
  }
}

/**
 * Translate a workout/run's totals into the gear's measurement unit and
 * increment `currentValue`. Caller passes whichever metrics are available
 * (distanceMeters preferred for shoes/bikes, durationSeconds for chest
 * strap / other, session count otherwise).
 */
export function computeGearIncrement(
  unit: 'miles' | 'km' | 'hours' | 'sessions',
  opts: { distanceMeters?: number | null; durationSeconds?: number | null },
): number {
  const distanceMeters = opts.distanceMeters ?? 0;
  const durationSeconds = opts.durationSeconds ?? 0;

  switch (unit) {
    case 'miles':
      return distanceMeters > 0 ? distanceMeters / 1609.344 : 0;
    case 'km':
      return distanceMeters > 0 ? distanceMeters / 1000 : 0;
    case 'hours':
      return durationSeconds > 0 ? durationSeconds / 3600 : 0;
    case 'sessions':
    default:
      return 1;
  }
}

/**
 * Convenience: increment usage on a single gear. Used by the workout/run
 * completion handlers. Returns the updated gear or null if nothing was
 * incremented (e.g. gear retired mid-session, or amount was zero).
 */
export async function incrementGearForWorkoutMetrics(
  gearId: Types.ObjectId,
  userId: Types.ObjectId,
  opts: { distanceMeters?: number | null; durationSeconds?: number | null },
): Promise<IGearComponent | null> {
  const gear = await GearComponent.findOne({ _id: gearId, userId, retiredAt: null });
  if (!gear) {
    return null;
  }
  const amount = computeGearIncrement(gear.unit, opts);
  if (amount <= 0) {
    return null;
  }
  return logGearUsage(gear._id, userId, amount);
}
