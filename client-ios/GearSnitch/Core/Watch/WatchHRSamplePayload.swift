import Foundation

// MARK: - Watch Heart Rate Sample Payload
//
// Shared wire format used by the Watch companion when it forwards a
// heart-rate sample to the iPhone over WatchConnectivity (either
// `sendMessage` when reachable or `transferUserInfo` as a queued fallback).
//
// The Watch side owns writes to this payload (it produces the samples).
// The iPhone side decodes and hands them off to
// `HeartRateMonitor.ingestWatchSample(bpm:timestamp:)` so the split
// Watch/AirPods Dashboard chart picks them up before HealthKit's own
// auto-sync surfaces the same sample.
//
// Keep this file self-contained and ABI-stable: adding fields is fine, but
// renaming/removing is a wire-compatibility break that needs to land on
// both sides in lock-step.

/// A single heart-rate sample produced on Apple Watch and forwarded to the
/// iPhone over WatchConnectivity.
struct WatchHRSamplePayload: Codable, Equatable {
    /// Beats per minute, rounded to the nearest integer on the Watch side.
    let bpm: Int

    /// The timestamp the reading was taken on the Watch. Send the Watch's
    /// clock value — the iPhone trusts the paired Watch's time to correlate
    /// with AirPods readings.
    let recordedAt: Date

    /// Optional raw source label (e.g. "Apple Watch Series 10"). The iPhone
    /// already classifies this as `.watch` by kind, but the raw string is
    /// useful for logs and debugging.
    let sourceDeviceName: String?

    init(bpm: Int, recordedAt: Date, sourceDeviceName: String? = nil) {
        self.bpm = bpm
        self.recordedAt = recordedAt
        self.sourceDeviceName = sourceDeviceName
    }

    // MARK: - Dictionary Bridging (WatchConnectivity Interop)

    /// Encode to a `[String: Any]` for `WCSession.sendMessage` /
    /// `transferUserInfo`, both of which accept only property-list types.
    func toDictionary() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    /// Decode from a `[String: Any]` received over WatchConnectivity.
    static func from(dictionary: [String: Any]) -> WatchHRSamplePayload? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchHRSamplePayload.self, from: data)
    }
}

// MARK: - Message Key

/// Key used to mark a WatchConnectivity message (or userInfo transfer) as
/// a heart-rate sample payload. Receivers check for this key to route the
/// message to `WatchHRSamplePayload.from(dictionary:)`.
enum WatchHRSampleMessageKey {
    /// Namespaced under the existing message-type envelope for consistency
    /// with the rest of `WatchSyncManager`.
    static let type = "hrSample"
}
