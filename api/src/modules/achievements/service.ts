import { Types } from 'mongoose';
import { Achievement } from '../../models/Achievement.js';
import { Run } from '../../models/Run.js';
import { Workout } from '../../models/Workout.js';
import { Device } from '../../models/Device.js';
import { Subscription } from '../../models/Subscription.js';
import logger from '../../utils/logger.js';

/**
 * Backlog item #39 — achievement badges.
 *
 * Server-authoritative badge catalog + rule engine. Pure functions evaluate
 * each rule against the caller-supplied activity counts; `checkAndAwardFor`
 * does the I/O (fetch counts, insert rows).
 *
 * Awarding is idempotent: the unique (userId, badgeId) index on
 * `Achievement` guarantees at most one row per user+badge. The service
 * swallows duplicate-key errors and treats them as "already earned".
 */

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

export type BadgeId =
  | 'first_run'
  | 'first_workout'
  | 'first_device_paired'
  | 'first_purchase'
  | 'streak_7d'
  | 'streak_30d'
  | 'hundred_sessions'
  | 'hundred_miles';

export const BADGE_IDS: readonly BadgeId[] = [
  'first_run',
  'first_workout',
  'first_device_paired',
  'first_purchase',
  'streak_7d',
  'streak_30d',
  'hundred_sessions',
  'hundred_miles',
] as const;

export type AchievementTrigger =
  | 'runCompleted'
  | 'workoutCompleted'
  | 'devicePaired'
  | 'subscriptionCharged';

export interface BadgeDefinition {
  id: BadgeId;
  title: string;
  description: string;
  /** SF Symbol name mirrored by the iOS client. */
  icon: string;
  /** Triggers that can ever award this badge. */
  triggers: readonly AchievementTrigger[];
}

export const BADGE_CATALOG: readonly BadgeDefinition[] = [
  {
    id: 'first_run',
    title: 'First Run',
    description: 'Completed your first run.',
    icon: 'figure.run',
    triggers: ['runCompleted'],
  },
  {
    id: 'first_workout',
    title: 'First Workout',
    description: 'Logged your first workout session.',
    icon: 'figure.strengthtraining.traditional',
    triggers: ['workoutCompleted'],
  },
  {
    id: 'first_device_paired',
    title: 'Connected',
    description: 'Paired your first device.',
    icon: 'sensor.tag.radiowaves.forward.fill',
    triggers: ['devicePaired'],
  },
  {
    id: 'first_purchase',
    title: 'Supporter',
    description: 'First subscription charge succeeded.',
    icon: 'crown.fill',
    triggers: ['subscriptionCharged'],
  },
  {
    id: 'streak_7d',
    title: '7-Day Streak',
    description: '7 consecutive days with at least one activity.',
    icon: 'flame.fill',
    triggers: ['runCompleted', 'workoutCompleted'],
  },
  {
    id: 'streak_30d',
    title: '30-Day Streak',
    description: '30 consecutive days with at least one activity.',
    icon: 'flame.circle.fill',
    triggers: ['runCompleted', 'workoutCompleted'],
  },
  {
    id: 'hundred_sessions',
    title: 'Century Club',
    description: '100 total workout sessions.',
    icon: 'star.circle.fill',
    triggers: ['workoutCompleted'],
  },
  {
    id: 'hundred_miles',
    title: '100 Miles',
    description: '100 total miles logged across runs.',
    icon: 'medal.fill',
    triggers: ['runCompleted'],
  },
];

const METERS_PER_MILE = 1_609.344;

// ---------------------------------------------------------------------------
// Pure rule evaluators
// ---------------------------------------------------------------------------

export interface UserActivityStats {
  runCount: number;
  workoutCount: number;
  deviceCount: number;
  subscriptionChargeCount: number;
  totalRunMeters: number;
  /** Longest streak in consecutive UTC days ending on the most recent day with activity. */
  currentStreakDays: number;
}

/** Pure: does the stats snapshot satisfy the rule for `badgeId`? */
export function evaluateBadgeRule(
  badgeId: BadgeId,
  stats: UserActivityStats,
): boolean {
  switch (badgeId) {
    case 'first_run':
      return stats.runCount >= 1;
    case 'first_workout':
      return stats.workoutCount >= 1;
    case 'first_device_paired':
      return stats.deviceCount >= 1;
    case 'first_purchase':
      return stats.subscriptionChargeCount >= 1;
    case 'streak_7d':
      return stats.currentStreakDays >= 7;
    case 'streak_30d':
      return stats.currentStreakDays >= 30;
    case 'hundred_sessions':
      return stats.workoutCount >= 100;
    case 'hundred_miles':
      return stats.totalRunMeters >= 100 * METERS_PER_MILE;
    default:
      return false;
  }
}

function makeProgress(current: number, target: number, unit: string) {
  const clamped = Math.min(Math.max(current, 0), target);
  return { current: clamped, target, label: `${clamped}/${target} ${unit}` };
}

/** Pure: human-readable progress hint (e.g. "2/7 day streak", "34/100 sessions"). */
export function progressFor(
  badgeId: BadgeId,
  stats: UserActivityStats,
): { current: number; target: number; label: string } | null {
  switch (badgeId) {
    case 'first_run':
      return makeProgress(stats.runCount, 1, 'run');
    case 'first_workout':
      return makeProgress(stats.workoutCount, 1, 'workout');
    case 'first_device_paired':
      return makeProgress(stats.deviceCount, 1, 'device');
    case 'first_purchase':
      return makeProgress(stats.subscriptionChargeCount, 1, 'purchase');
    case 'streak_7d':
      return makeProgress(stats.currentStreakDays, 7, 'day streak');
    case 'streak_30d':
      return makeProgress(stats.currentStreakDays, 30, 'day streak');
    case 'hundred_sessions':
      return makeProgress(stats.workoutCount, 100, 'sessions');
    case 'hundred_miles':
      return makeProgress(Math.floor(stats.totalRunMeters / METERS_PER_MILE), 100, 'miles');
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Streak calculation (pure)
// ---------------------------------------------------------------------------

/**
 * Compute the user's current streak ending on `referenceDate` (defaults to
 * "today" in UTC). A streak is a maximal run of consecutive UTC calendar
 * days on each of which the user had at least one activity.
 *
 * If the most recent activity was >1 day before `referenceDate`, the
 * streak is 0. If it was on `referenceDate` or the day before (yesterday),
 * the streak is still "alive" and counted back from that day.
 *
 * `activityDates` — a list of activity dates (runs + workouts etc). Only
 * the day-bucket matters; duplicates within a day are collapsed.
 */
export function computeCurrentStreakDays(
  activityDates: Date[],
  referenceDate: Date = new Date(),
): number {
  if (activityDates.length === 0) {
    return 0;
  }

  const toDayKey = (d: Date): number => {
    const y = d.getUTCFullYear();
    const m = d.getUTCMonth();
    const day = d.getUTCDate();
    return Date.UTC(y, m, day);
  };

  const dayMs = 24 * 60 * 60 * 1000;
  const days = new Set<number>();
  for (const d of activityDates) {
    days.add(toDayKey(d));
  }

  const todayKey = toDayKey(referenceDate);
  const yesterdayKey = todayKey - dayMs;

  // Anchor: today if today had activity, otherwise yesterday if yesterday did,
  // otherwise the streak is 0.
  let cursor: number;
  if (days.has(todayKey)) {
    cursor = todayKey;
  } else if (days.has(yesterdayKey)) {
    cursor = yesterdayKey;
  } else {
    return 0;
  }

  let streak = 0;
  while (days.has(cursor)) {
    streak += 1;
    cursor -= dayMs;
  }
  return streak;
}

// ---------------------------------------------------------------------------
// Service — awarding + reading
// ---------------------------------------------------------------------------

/**
 * Idempotent insert. Returns true if a new row was created; false if the
 * user already held the badge (duplicate key swallowed).
 */
async function insertIfAbsent(
  userId: Types.ObjectId,
  badgeId: BadgeId,
  metadata: Record<string, unknown> | null,
): Promise<boolean> {
  try {
    await Achievement.create({
      userId,
      badgeId,
      earnedAt: new Date(),
      metadata,
    });
    return true;
  } catch (err: unknown) {
    const e = err as { code?: number };
    if (e?.code === 11000) {
      return false;
    }
    throw err;
  }
}

/**
 * Fetch the minimum stats needed to evaluate all badge rules for this user.
 * Counts are deliberately single-collection so this stays cheap; streak
 * uses a limited scan of recent activity dates.
 */
export async function loadUserActivityStats(
  userId: Types.ObjectId,
): Promise<UserActivityStats> {
  // 90 days of activity dates is enough to compute a 30-day streak with
  // plenty of margin. Pull both `endedAt` (workouts/runs both use this)
  // and `startedAt` as a fallback so a run that only has `startedAt`
  // still counts toward today.
  const since = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);

  // First-purchase is defined as "at least one Subscription row that has
  // ever reached a paid state". We treat any status except `revoked`/`refunded`
  // as evidence of a successful charge — `active`/`past_due`/`cancelled`/
  // `grace_period`/`expired` all imply the user was billed at least once.
  const [
    runCount,
    workoutCount,
    runAgg,
    recentRuns,
    recentWorkouts,
    deviceCount,
    subscriptionChargeCount,
  ] = await Promise.all([
    Run.countDocuments({ userId, endedAt: { $ne: null } }),
    Workout.countDocuments({ userId, endedAt: { $ne: null } }),
    Run.aggregate<{ _id: null; total: number }>([
      { $match: { userId, endedAt: { $ne: null } } },
      { $group: { _id: null, total: { $sum: '$distanceMeters' } } },
    ]),
    Run.find({ userId, endedAt: { $gte: since } })
      .select({ endedAt: 1, startedAt: 1, _id: 0 })
      .lean(),
    Workout.find({ userId, endedAt: { $gte: since } })
      .select({ endedAt: 1, startedAt: 1, _id: 0 })
      .lean(),
    Device.countDocuments({ userId }),
    Subscription.countDocuments({
      userId,
      status: { $in: ['active', 'past_due', 'cancelled', 'grace_period', 'expired'] },
    }),
  ]);

  const activityDates: Date[] = [];
  for (const r of recentRuns) {
    const d = (r.endedAt as Date | null | undefined) ?? (r.startedAt as Date | undefined);
    if (d) activityDates.push(d);
  }
  for (const w of recentWorkouts) {
    const d = (w.endedAt as Date | null | undefined) ?? (w.startedAt as Date | undefined);
    if (d) activityDates.push(d);
  }

  return {
    runCount,
    workoutCount,
    deviceCount,
    subscriptionChargeCount,
    totalRunMeters: runAgg[0]?.total ?? 0,
    currentStreakDays: computeCurrentStreakDays(activityDates),
  };
}

/**
 * Evaluate all badges applicable to this trigger and award any that are
 * satisfied and not yet earned. Safe to call on every trigger firing.
 *
 * Failures are logged but swallowed — awards are best-effort and must
 * never break the primary request path.
 */
export async function checkAndAwardFor(
  userId: Types.ObjectId | string,
  trigger: AchievementTrigger,
  correlationId?: string,
): Promise<BadgeId[]> {
  const uid = typeof userId === 'string' ? new Types.ObjectId(userId) : userId;
  try {
    const stats = await loadUserActivityStats(uid);
    const existing = await Achievement.find({ userId: uid })
      .select({ badgeId: 1, _id: 0 })
      .lean();
    const held = new Set(existing.map((e) => e.badgeId));

    const applicable = BADGE_CATALOG.filter((b) => b.triggers.includes(trigger));
    const awarded: BadgeId[] = [];

    for (const def of applicable) {
      if (held.has(def.id)) continue;
      if (!evaluateBadgeRule(def.id, stats)) continue;
      const inserted = await insertIfAbsent(uid, def.id, {
        trigger,
        stats: {
          runCount: stats.runCount,
          workoutCount: stats.workoutCount,
          currentStreakDays: stats.currentStreakDays,
        },
      });
      if (inserted) {
        awarded.push(def.id);
      }
    }

    if (awarded.length > 0) {
      logger.info('Achievements awarded', {
        correlationId,
        userId: String(uid),
        trigger,
        awarded,
      });
    }
    return awarded;
  } catch (err) {
    logger.warn('checkAndAwardFor failed (non-fatal)', {
      correlationId,
      userId: String(uid),
      trigger,
      error: err instanceof Error ? err.message : String(err),
    });
    return [];
  }
}

/**
 * Read all achievements for a user, plus progress hints for unearned badges.
 */
export async function getAchievementsWithProgress(
  userId: Types.ObjectId,
): Promise<{
  earned: Array<{ badgeId: BadgeId; earnedAt: Date; definition: BadgeDefinition }>;
  locked: Array<{
    badgeId: BadgeId;
    definition: BadgeDefinition;
    progress: { current: number; target: number; label: string } | null;
  }>;
  stats: UserActivityStats;
}> {
  const [rows, stats] = await Promise.all([
    Achievement.find({ userId }).lean(),
    loadUserActivityStats(userId),
  ]);

  const earnedMap = new Map<string, Date>();
  for (const r of rows) {
    earnedMap.set(r.badgeId, r.earnedAt as Date);
  }

  const earned: Array<{ badgeId: BadgeId; earnedAt: Date; definition: BadgeDefinition }> = [];
  const locked: Array<{
    badgeId: BadgeId;
    definition: BadgeDefinition;
    progress: { current: number; target: number; label: string } | null;
  }> = [];

  for (const def of BADGE_CATALOG) {
    const earnedAt = earnedMap.get(def.id);
    if (earnedAt) {
      earned.push({ badgeId: def.id, earnedAt, definition: def });
    } else {
      locked.push({ badgeId: def.id, definition: def, progress: progressFor(def.id, stats) });
    }
  }

  return { earned, locked, stats };
}
