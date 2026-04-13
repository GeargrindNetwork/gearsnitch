import mongoose, { Schema, Document, Types } from 'mongoose';

export const EVENT_TYPES = [
  'session_start',
  'session_end',
  'device_connect',
  'device_disconnect',
  'gym_entry',
  'gym_exit',
  'alarm_triggered',
  'purchase',
  'meal_logged',
  'water_logged',
  'workout_started',
  'workout_ended',
  'profile_updated',
] as const;

export type EventType = (typeof EVENT_TYPES)[number];

export interface IEventLog extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  eventType: EventType;
  metadata?: unknown;
  source: 'ios' | 'web' | 'system' | 'widget';
  timestamp: Date;
}

const EventLogSchema = new Schema<IEventLog>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    eventType: {
      type: String,
      required: true,
      enum: EVENT_TYPES,
    },
    metadata: { type: Schema.Types.Mixed },
    source: {
      type: String,
      enum: ['ios', 'web', 'system', 'widget'],
      default: 'ios',
    },
    timestamp: { type: Date, default: Date.now },
  },
  { timestamps: { createdAt: true, updatedAt: false } },
);

EventLogSchema.index({ userId: 1, timestamp: -1 });
EventLogSchema.index({ eventType: 1 });

export const EventLog = mongoose.model<IEventLog>('EventLog', EventLogSchema);
