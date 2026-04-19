import Foundation

// MARK: - iPhone → Watch Application Context

struct WatchAppContext: Codable {
    let isSessionActive: Bool
    let sessionGymName: String?
    let sessionStartedAt: Date?
    let sessionElapsedSeconds: Int?
    let heartRateBPM: Int?
    let heartRateZone: String?
    let heartRateSourceDevice: String?
    let activeAlertCount: Int
    let defaultGymId: String?
    let defaultGymName: String?
    let isHeartRateMonitoring: Bool

    static let empty = WatchAppContext(
        isSessionActive: false,
        sessionGymName: nil,
        sessionStartedAt: nil,
        sessionElapsedSeconds: nil,
        heartRateBPM: nil,
        heartRateZone: nil,
        heartRateSourceDevice: nil,
        activeAlertCount: 0,
        defaultGymId: nil,
        defaultGymName: nil,
        isHeartRateMonitoring: false
    )

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    static func from(dictionary: [String: Any]) -> WatchAppContext? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchAppContext.self, from: data)
    }
}

// MARK: - Watch → iPhone Application Context

struct PhoneAppContext: Codable {
    let watchActive: Bool
    let lastInteractionAt: Date?

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    static func from(dictionary: [String: Any]) -> PhoneAppContext? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(PhoneAppContext.self, from: data)
    }
}

// MARK: - Live Message Types

enum WatchMessageType: String {
    case heartRate
    case sessionUpdate
    case alertUpdate
    case sessionCommand
    case alertAcknowledge
    case hrMonitoring
    case watchHRSample
    case workoutState
    case paceCoachHaptic
}

enum WatchSessionAction: String, Codable {
    case start
    case end
}

// MARK: - Watch → iPhone HR Sample Payload

/// Single heart rate sample originating on the Apple Watch (HealthKit / live workout
/// builder). Sent both as a queued `transferUserInfo` payload (reliable, batched) and
/// as a live `sendMessage` payload during active workouts (low-latency).
struct WatchHRSamplePayload: Codable, Equatable {
    let bpm: Double
    let timestamp: Date
    let source: String          // e.g. "Apple Watch"
    let withinWorkout: Bool

    /// Optional secondary key embedded in `userInfo` payloads so the receiver can
    /// distinguish HR samples from other queued message types.
    static let userInfoTypeKey = "type"
    static let userInfoTypeValue = "watchHRSample"

    func toUserInfo() -> [String: Any] {
        guard let data = try? JSONEncoder.gearSnitchISO.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var enriched = dict
        enriched[Self.userInfoTypeKey] = Self.userInfoTypeValue
        return enriched
    }

    static func from(userInfo: [String: Any]) -> WatchHRSamplePayload? {
        var dict = userInfo
        dict.removeValue(forKey: Self.userInfoTypeKey)
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        return try? JSONDecoder.gearSnitchISO.decode(WatchHRSamplePayload.self, from: data)
    }
}

// MARK: - Watch → iPhone Workout State Payload

enum WatchWorkoutState: String, Codable {
    case idle
    case running
    case paused
    case ended
}

struct WatchWorkoutStatePayload: Codable, Equatable {
    let state: WatchWorkoutState
    let startedAt: Date?
    let endedAt: Date?
    let totalSamples: Int

    func toMessage() -> [String: Any] {
        guard let data = try? JSONEncoder.gearSnitchISO.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var enriched = dict
        enriched[WatchHRSamplePayload.userInfoTypeKey] = WatchMessageType.workoutState.rawValue
        return enriched
    }

    static func from(message: [String: Any]) -> WatchWorkoutStatePayload? {
        var dict = message
        dict.removeValue(forKey: WatchHRSamplePayload.userInfoTypeKey)
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        return try? JSONDecoder.gearSnitchISO.decode(WatchWorkoutStatePayload.self, from: data)
    }
}

// MARK: - iPhone → Watch Pace-Coach Haptic Payload (Backlog item #21)

/// Tells the Watch to fire a haptic nudge when the runner drifts off
/// target pace. The iPhone owns the decision logic (GPS is there); the
/// Watch is a pure effector that dedupes on its own 30s window in case
/// WC delivers duplicates.
///
/// `kind` mirrors `HapticNudge` from `RunPaceCoach.swift`:
///   - "directionUp"   → speed up
///   - "directionDown" → slow down
struct PaceCoachHapticMessage: Codable, Equatable {
    let kind: String
    let sentAt: Date

    static let messageTypeValue = WatchMessageType.paceCoachHaptic.rawValue

    func toMessage() -> [String: Any] {
        guard let data = try? JSONEncoder.gearSnitchISO.encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var enriched = dict
        enriched[WatchHRSamplePayload.userInfoTypeKey] = Self.messageTypeValue
        return enriched
    }

    static func from(message: [String: Any]) -> PaceCoachHapticMessage? {
        var dict = message
        dict.removeValue(forKey: WatchHRSamplePayload.userInfoTypeKey)
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        return try? JSONDecoder.gearSnitchISO.decode(PaceCoachHapticMessage.self, from: data)
    }
}

// MARK: - Codable helpers

extension JSONEncoder {
    static let gearSnitchISO: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let gearSnitchISO: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
