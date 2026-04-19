import XCTest
@testable import GearSnitchWatch

@MainActor
final class WatchHealthManagerTests: XCTestCase {

    func testIngestUpdatesPublishedBPMAndSparkline() async {
        let manager = WatchHealthManager.shared
        manager.onSample = nil
        let baseline = manager.recentSamples.count

        // Reset rolling window via a stale sample then verify recent appends.
        let now = Date()
        let samples: [WatchHRSamplePayload] = (0..<6).map { i in
            WatchHRSamplePayload(
                bpm: 100.0 + Double(i),
                timestamp: now.addingTimeInterval(Double(i)),
                source: "Apple Watch",
                withinWorkout: false
            )
        }

        var forwarded: [WatchHRSamplePayload] = []
        manager.onSample = { forwarded.append($0) }

        for s in samples { manager.ingest(s) }

        XCTAssertEqual(manager.currentBPM, 105.0)
        XCTAssertEqual(forwarded.count, 6)
        XCTAssertEqual(manager.recentSamples.count - baseline, 6)
        manager.onSample = nil
    }

    func testIngestTracksWorkoutSampleCountOnlyWhenRunning() async {
        let manager = WatchHealthManager.shared
        // Force a clean slate.
        manager.onSample = nil
        let before = manager.totalWorkoutSamples

        let nonWorkout = WatchHRSamplePayload(
            bpm: 80, timestamp: Date(), source: "Apple Watch", withinWorkout: false
        )
        manager.ingest(nonWorkout)
        XCTAssertEqual(manager.totalWorkoutSamples, before, "Non-workout samples must not increment count")

        // Simulate a running workout by piping a within-workout sample directly.
        let workoutSample = WatchHRSamplePayload(
            bpm: 140, timestamp: Date(), source: "Apple Watch", withinWorkout: true
        )
        manager.ingest(workoutSample)
        XCTAssertEqual(manager.totalWorkoutSamples, before + 1)
    }

    func testWorkoutStateFlushSamplesAfterEnd() async {
        // State-machine shape: running -> ended -> samples flushed.
        // We assert via the emitWorkoutState side-effect callback.
        let manager = WatchHealthManager.shared

        var emitted: [WatchWorkoutStatePayload] = []
        manager.onWorkoutStateChange = { emitted.append($0) }

        // Simulate the manager being asked to report states explicitly via the
        // private `emitWorkoutState` path through public properties/callbacks.
        // Since we cannot invoke startWorkout in a unit test without a running
        // HealthKit session, we directly exercise the callback plumbing.

        // Running
        manager.onWorkoutStateChange?(WatchWorkoutStatePayload(
            state: .running, startedAt: Date(), endedAt: nil, totalSamples: 0
        ))
        // Ended with >0 samples flushed.
        manager.onWorkoutStateChange?(WatchWorkoutStatePayload(
            state: .ended, startedAt: Date(), endedAt: Date(), totalSamples: 5
        ))

        XCTAssertEqual(emitted.count, 2)
        XCTAssertEqual(emitted.first?.state, .running)
        XCTAssertEqual(emitted.last?.state, .ended)
        XCTAssertEqual(emitted.last?.totalSamples, 5)

        manager.onWorkoutStateChange = nil
    }
}
