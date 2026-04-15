import ActivityKit
import Foundation

struct GymSessionAttributes: ActivityAttributes {
    let gymName: String
    let startedAt: Date

    struct ContentState: Codable, Hashable {
        let isActive: Bool
        let elapsedSeconds: Int
        let heartRateBPM: Int?
        let heartRateZone: String?
    }
}
