import mongoose, { Schema, Document, Types } from 'mongoose';

/**
 * Individual RSSI (Received Signal Strength Indicator) reading captured
 * by the iOS `BLEManager` while a paired BLE device is advertising or
 * connected (backlog item #19).
 *
 * Stored per user + device so `DeviceDetailView` can render a 24h line
 * chart and compute a week-over-week signal drift delta. A week of
 * samples is plenty for the chart + WoW math — a TTL index drops the
 * rest automatically so this collection can't grow unbounded on a
 * chatty peripheral that reports every few seconds.
 *
 * RSSI values are in dBm. Typical BLE range is roughly -30 dBm (device
 * almost touching the phone) to -100 dBm (on the edge of losing the
 * connection). We accept and store the full `[-120, 0]` range so we
 * don't silently drop odd outlier readings.
 */
export interface IRssiSample extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  deviceId: Types.ObjectId;
  rssi: number;
  sampledAt: Date;
}

const RssiSampleSchema = new Schema<IRssiSample>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    deviceId: { type: Schema.Types.ObjectId, ref: 'Device', required: true },
    rssi: {
      type: Number,
      required: true,
      min: -120,
      max: 0,
    },
    sampledAt: { type: Date, required: true, default: () => new Date() },
  },
  { versionKey: false }
);

// Fast per-device time-series reads (GET /devices/:id/rssi/history).
RssiSampleSchema.index({ deviceId: 1, sampledAt: -1 });

// TTL: purge after 7 days (604800 seconds). The 24h chart only needs
// the last day, and the week-over-week comparison needs ~8 days of
// headroom. 7 days keeps the collection bounded while still covering
// the primary user-facing queries.
RssiSampleSchema.index(
  { sampledAt: 1 },
  { expireAfterSeconds: 60 * 60 * 24 * 7 }
);

export const RssiSample = mongoose.model<IRssiSample>(
  'RssiSample',
  RssiSampleSchema
);
