import ActivityKit
import Foundation

struct DisconnectProtectionAttributes: ActivityAttributes {
    let armedAt: Date
    let gymName: String?

    struct ContentState: Codable, Hashable {
        let isArmed: Bool
        let connectedDeviceCount: Int
        let countdownSeconds: Int?
        let disconnectedDeviceName: String?
    }
}
