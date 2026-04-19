import mongoose, { Schema, Document, Types } from 'mongoose';

/**
 * Backlog item #39 — achievement badges.
 *
 * One row per (userId, badgeId). A user who has earned a badge has exactly
 * one row; re-awarding is a no-op thanks to the unique compound index below.
 * The `earnedAt` timestamp records first-issue time; the `metadata` blob
 * captures the trigger context (e.g. which run/workout crossed the threshold)
 * so the UI can render "Earned 7d streak on Apr 12" without another query.
 */
export interface IAchievement extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  badgeId: string;
  earnedAt: Date;
  metadata: Record<string, unknown> | null;
  createdAt: Date;
  updatedAt: Date;
}

const AchievementSchema = new Schema<IAchievement>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    badgeId: { type: String, required: true },
    earnedAt: { type: Date, required: true, default: () => new Date() },
    metadata: { type: Schema.Types.Mixed, default: null },
  },
  { timestamps: true },
);

// Idempotency guard — one badge per user. An upsert/insert that violates
// this index is swallowed by the service layer and treated as a no-op.
AchievementSchema.index({ userId: 1, badgeId: 1 }, { unique: true });
AchievementSchema.index({ userId: 1, earnedAt: -1 });

export const Achievement = mongoose.model<IAchievement>(
  'Achievement',
  AchievementSchema,
);
