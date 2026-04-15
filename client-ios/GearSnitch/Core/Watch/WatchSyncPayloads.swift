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
}

enum WatchSessionAction: String, Codable {
    case start
    case end
}
