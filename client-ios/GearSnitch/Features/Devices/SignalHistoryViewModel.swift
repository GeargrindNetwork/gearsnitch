import Foundation
import os

/// Drives the "Signal History" section on `DeviceDetailView` (backlog
/// item #19). Fetches the 24h bucketed RSSI history from the backend,
/// exposes a loading/error state, and derives the week-over-week drop
/// banner threshold.
@MainActor
final class SignalHistoryViewModel: ObservableObject {

    // MARK: - Published

    @Published private(set) var isLoading = false
    @Published private(set) var history: SignalHistoryResponse?
    @Published private(set) var errorMessage: String?

    // MARK: - Config

    /// A drop of 15+ dBm week-over-week is roughly a 32x decrease in
    /// signal power — large enough to flag placement or battery as a
    /// likely cause.
    static let weekOverWeekWarningThreshold: Double = -15

    let deviceId: String
    let windowHours: Int
    let buckets: Int

    private let service: SignalHistoryServicing
    private let logger = Logger(subsystem: "com.gearsnitch", category: "SignalHistoryViewModel")

    // MARK: - Init

    init(
        deviceId: String,
        windowHours: Int = 24,
        buckets: Int = 60,
        service: SignalHistoryServicing = SignalHistoryService.shared
    ) {
        self.deviceId = deviceId
        self.windowHours = windowHours
        self.buckets = buckets
        self.service = service
    }

    // MARK: - Derived

    /// `true` when the week-over-week delta crosses the warning
    /// threshold. UI renders a callout banner when this is set.
    var shouldShowWeeklyDropWarning: Bool {
        guard let delta = history?.weekOverWeekDelta else { return false }
        return delta <= Self.weekOverWeekWarningThreshold
    }

    /// Human-readable drop amount in dBm (absolute value, rounded) for
    /// the warning banner copy.
    var weeklyDropDbm: Int {
        guard let delta = history?.weekOverWeekDelta else { return 0 }
        return Int(abs(delta).rounded())
    }

    // MARK: - Actions

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            history = try await service.fetchHistory(
                deviceId: deviceId,
                windowHours: windowHours,
                buckets: buckets
            )
        } catch {
            logger.warning("Failed to load RSSI history: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
