import Foundation
import Combine

// MARK: - Lap Entry

struct LapEntry: Identifiable {
    let id = UUID()
    let number: Int
    let splitTime: TimeInterval
    let totalTime: TimeInterval
}

// MARK: - Stopwatch View Model

@MainActor
final class StopwatchViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var laps: [LapEntry] = []

    // MARK: - Private

    private var timerCancellable: AnyCancellable?
    private var startDate: Date?
    private var accumulatedTime: TimeInterval = 0
    private var lastLapTime: TimeInterval = 0

    // MARK: - Formatted Time

    /// Returns the elapsed time formatted as HH:MM:SS.cc (centiseconds).
    var formattedTime: String {
        Self.format(elapsedTime)
    }

    static func format(_ time: TimeInterval) -> String {
        let totalCentiseconds = Int(time * 100)
        let hours = totalCentiseconds / 360_000
        let minutes = (totalCentiseconds % 360_000) / 6_000
        let seconds = (totalCentiseconds % 6_000) / 100
        let centiseconds = totalCentiseconds % 100

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
        } else {
            return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
        }
    }

    /// Format a split time for lap display.
    static func formatSplit(_ time: TimeInterval) -> String {
        format(time)
    }

    // MARK: - Actions

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startDate = Date()

        timerCancellable = Timer.publish(every: 0.01, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let startDate = self.startDate else { return }
                self.elapsedTime = self.accumulatedTime + Date().timeIntervalSince(startDate)
            }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let startDate {
            accumulatedTime += Date().timeIntervalSince(startDate)
        }
        startDate = nil
        timerCancellable?.cancel()
        timerCancellable = nil
        elapsedTime = accumulatedTime
    }

    func lap() {
        guard isRunning else { return }

        let currentTime = elapsedTime
        let splitTime = currentTime - lastLapTime
        lastLapTime = currentTime

        let entry = LapEntry(
            number: laps.count + 1,
            splitTime: splitTime,
            totalTime: currentTime
        )
        laps.insert(entry, at: 0) // newest first
    }

    func reset() {
        stop()
        elapsedTime = 0
        accumulatedTime = 0
        lastLapTime = 0
        laps.removeAll()
    }
}
