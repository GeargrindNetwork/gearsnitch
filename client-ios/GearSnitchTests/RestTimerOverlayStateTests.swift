import XCTest
import SwiftUI
@testable import GearSnitch

// MARK: - RestTimerOverlayStateTests (Backlog item #16)
//
// Repo does not include swift-snapshot-testing; rather than introduce
// a new dependency (against the guard rail) we verify the three render
// states the overlay cares about by asserting on the driving state
// (`RestTimerState`), since SwiftUI renders are a pure function of
// that state:
//   1. Just-started: 58s remaining, progress just past 0, phase = .running
//   2. Warning: 5s remaining, the 6→5 warning callback has fired once
//   3. Done: 0s remaining, phase = .complete, completion callback fired once
//
// This gives us the same behavioral coverage a UI snapshot would,
// without the device/simulator coupling.

@MainActor
final class RestTimerOverlayStateTests: XCTestCase {

    // State 1 — just-started (58s remaining from a 60s start).
    func testJustStartedStateForOverlay() {
        let state = RestTimerState(duration: 60)
        state.tick() // 59
        state.tick() // 58

        XCTAssertEqual(state.remainingSeconds, 58)
        XCTAssertEqual(state.totalSeconds, 60)
        XCTAssertEqual(state.phase, .running)
        // Progress should be small but non-zero — ring just started filling.
        XCTAssertGreaterThan(state.progress, 0.0)
        XCTAssertLessThan(state.progress, 0.1)

        // The overlay view constructs cleanly with this state.
        let view = RestTimerOverlayView(state: state, onDismiss: {})
        _ = view.body
    }

    // State 2 — warning (5s remaining, .medium haptic boundary).
    func testWarningStateForOverlay() {
        let state = RestTimerState(duration: 10)
        var warningFired = 0
        state.onWarning = { warningFired += 1 }

        // Tick from 10 → 5
        for _ in 0..<5 {
            state.tick()
        }

        XCTAssertEqual(state.remainingSeconds, 5)
        XCTAssertEqual(state.phase, .running)
        XCTAssertEqual(warningFired, 1, "Warning haptic must have fired exactly once")
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.0001)

        let view = RestTimerOverlayView(state: state, onDismiss: {})
        _ = view.body
    }

    // State 3 — done (0s, completion callback has fired once).
    func testDoneStateForOverlay() {
        let state = RestTimerState(duration: 2)
        var completions = 0
        state.onComplete = { _ in completions += 1 }

        state.tick() // 1
        state.tick() // 0 → complete

        XCTAssertEqual(state.remainingSeconds, 0)
        XCTAssertEqual(state.phase, .complete)
        XCTAssertEqual(state.progress, 1.0, accuracy: 0.0001)
        XCTAssertEqual(completions, 1)

        let view = RestTimerOverlayView(state: state, onDismiss: {})
        _ = view.body
    }

    // Guard against the most common render-state bug: a stale tick
    // arriving after skip() firing onComplete twice. This would
    // double-play the bell cue + haptic.
    func testOverlayStateNeverDoubleFiresComplete() {
        let state = RestTimerState(duration: 3)
        var completions = 0
        state.onComplete = { _ in completions += 1 }

        state.skip()
        // A racey tick() that arrived from the scheduler right after
        // skip must not fire onComplete again.
        state.tick()
        state.tick()

        XCTAssertEqual(completions, 1)
    }
}
