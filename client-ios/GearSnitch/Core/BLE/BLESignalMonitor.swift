import Foundation
import CoreBluetooth
import UIKit
import os

// MARK: - Signal Level

enum SignalLevel: Int, Comparable, CaseIterable {
    case strong = 0
    case moderate = 1
    case weak = 2
    case critical = 3
    case lost = 4

    static func < (lhs: SignalLevel, rhs: SignalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Classify an RSSI value into a signal level.
    static func from(rssi: Int) -> SignalLevel {
        switch rssi {
        case -60 ... 0:      return .strong
        case -75 ..< -60:    return .moderate
        case -85 ..< -75:    return .weak
        case -95 ..< -85:    return .critical
        default:             return .lost
        }
    }

    var description: String {
        switch self {
        case .strong:   return "Strong"
        case .moderate: return "Moderate"
        case .weak:     return "Weak"
        case .critical: return "Critical"
        case .lost:     return "Lost"
        }
    }

    var iconName: String {
        switch self {
        case .strong:   return "wifi"
        case .moderate: return "wifi"
        case .weak:     return "wifi.exclamationmark"
        case .critical: return "wifi.slash"
        case .lost:     return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var color: UIColor {
        switch self {
        case .strong:   return UIColor(red: 34/255, green: 197/255, blue: 94/255, alpha: 1)   // gsSuccess
        case .moderate: return UIColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 1)  // gsEmerald
        case .weak:     return UIColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1)  // gsWarning
        case .critical: return UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)   // gsDanger
        case .lost:     return UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)   // gsDanger
        }
    }

    /// Number of signal bars to display (1-4).
    var barCount: Int {
        switch self {
        case .strong:   return 4
        case .moderate: return 3
        case .weak:     return 2
        case .critical: return 1
        case .lost:     return 0
        }
    }

    /// Haptic style that escalates with degrading signal.
    var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .strong:   return .light
        case .moderate: return .light
        case .weak:     return .medium
        case .critical: return .heavy
        case .lost:     return .rigid
        }
    }

    /// Interval between haptic/chirp alerts. Nil means no periodic alert.
    var alertInterval: TimeInterval? {
        switch self {
        case .strong:   return nil
        case .moderate: return 5.0
        case .weak:     return 3.0
        case .critical: return 1.0
        case .lost:     return nil  // panic takes over
        }
    }
}

// MARK: - BLE Signal Monitor

/// Monitors RSSI for all connected BLE devices and triggers progressive
/// haptic/audio alerts as signal degrades.
@MainActor
final class BLESignalMonitor: ObservableObject {

    static let shared = BLESignalMonitor()

    // MARK: - Published State

    @Published private(set) var signalLevel: SignalLevel = .strong
    @Published private(set) var isAlarming: Bool = false

    /// Smoothed RSSI value computed from the history buffer.
    @Published private(set) var smoothedRSSI: Int = 0

    // MARK: - Configuration

    /// Number of recent RSSI samples to keep for smoothing.
    private let historySize = 10

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "com.gearsnitch", category: "BLESignalMonitor")
    private var rssiHistory: [Int] = []
    private var rssiTimer: Timer?
    private var alertTimer: Timer?
    private var hapticGenerator: UIImpactFeedbackGenerator?
    private let soundPlayer = BLEAlarmSoundPlayer.shared

    // MARK: - Init

    private init() {}

    // MARK: - Start / Stop Monitoring

    /// Begin periodic RSSI polling (every 1 second) for the given device.
    func startMonitoring() {
        guard rssiTimer == nil else { return }

        rssiHistory.removeAll()
        signalLevel = .strong
        isAlarming = false

        rssiTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestRSSIReadings()
            }
        }

        logger.info("Signal monitoring started")
    }

    /// Stop all monitoring and alarms.
    func stopMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        alertTimer?.invalidate()
        alertTimer = nil
        hapticGenerator = nil
        isAlarming = false
        rssiHistory.removeAll()
        soundPlayer.stop()

        logger.info("Signal monitoring stopped")
    }

    // MARK: - RSSI Processing

    /// Called by BLEManager when a new RSSI reading is received.
    func reportRSSI(_ rssi: Int, for device: BLEDevice) {
        // Append to history, keeping only the last N samples
        rssiHistory.append(rssi)
        if rssiHistory.count > historySize {
            rssiHistory.removeFirst(rssiHistory.count - historySize)
        }

        // Compute smoothed RSSI (simple moving average)
        let average = rssiHistory.reduce(0, +) / rssiHistory.count
        smoothedRSSI = average

        let newLevel = SignalLevel.from(rssi: average)
        let previousLevel = signalLevel

        if newLevel != previousLevel {
            signalLevel = newLevel
            logger.info("Signal level changed: \(previousLevel.description) -> \(newLevel.description) (RSSI: \(average))")
            reconfigureAlerts(for: newLevel)
        }
    }

    /// Called when a device disconnects unexpectedly.
    func reportDeviceLost(_ device: BLEDevice) {
        signalLevel = .lost
        reconfigureAlerts(for: .lost)
    }

    // MARK: - Alert Management

    private func reconfigureAlerts(for level: SignalLevel) {
        alertTimer?.invalidate()
        alertTimer = nil

        if level == .strong {
            isAlarming = false
            soundPlayer.stop()
            return
        }

        if level == .lost {
            // Panic takes over -- delegate to PanicAlarmManager
            isAlarming = false
            soundPlayer.stop()
            return
        }

        isAlarming = true

        // Fire an alert immediately for the new level
        fireAlert(for: level)

        // Schedule repeating alerts at the level's interval
        if let interval = level.alertInterval {
            alertTimer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.fireAlert(for: self.signalLevel)
                }
            }
        }
    }

    private func fireAlert(for level: SignalLevel) {
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: level.hapticStyle)
        generator.prepare()
        generator.impactOccurred()

        // Audio chirp (weak and critical levels)
        if level >= .weak {
            let intensity: Float = level == .critical ? 0.9 : 0.4
            soundPlayer.playChirp(intensity: intensity)
        }
    }

    // MARK: - Request RSSI Readings

    private func requestRSSIReadings() {
        let manager = BLEManager.shared
        for device in manager.connectedDevices {
            manager.readRSSI(for: device)
        }
    }
}
