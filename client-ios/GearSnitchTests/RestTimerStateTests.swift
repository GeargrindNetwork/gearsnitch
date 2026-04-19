import XCTest
@testable import GearSnitch

// MARK: - RestTimerStateTests (Backlog item #16)
//
// Covers the tick logic of the rest-timer sub-view-model:
//   - start → pause → resume → complete
//   - no double-complete on concurrent tick + skip
//   - warning callback fires exactly once at 6→5s boundary
//   - nudge clamps correctly
//
// Tests drive `tick()` directly instead of relying on the real-time
// scheduler (which would require a 60s wait for a natural completion).

@MainActor
final class RestTimerStateTests: XCTestCase {

    // MARK: - Tick progression

    func testTickDecrementsRemainingSeconds() {
        let state = RestTimerState(duration: 5)
        XCTAssertEqual(state.remainingSeconds, 5)

        state.tick()
        XCTAssertEqual(state.remainingSeconds, 4)

        state.tick()
        XCTAssertEqual(state.remainingSeconds, 3)
    }

    func testTickCompletesWhenReachingZero() {
        let state = RestTimerState(duration: 3)
        var completionCalls = 0
        var naturalFlag: Bool?
        state.onComplete = { natural in
            completionCalls += 1
            naturalFlag = natural
        }

        state.tick() // 2
        state.tick() // 1
        state.tick() // 0 → complete
        XCTAssertEqual(state.phase, .complete)
        XCTAssertEqual(state.remainingSeconds, 0)
        XCTAssertEqual(completionCalls, 1)
        XCTAssertEqual(naturalFlag, true)
    }

    // MARK: - Pause / resume

    func testPauseStopsTickProgression() {
        let state = RestTimerState(duration: 10)
        state.pause()
        state.tick()
        state.tick()
        XCTAssertEqual(state.remainingSeconds, 10, "Paused timer should not tick down")
        XCTAssertEqual(state.phase, .paused)
    }

    func testResumeAllowsTickToContinue() {
        let state = RestTimerState(duration: 10)
        state.pause()
        state.tick()
        XCTAssertEqual(state.remainingSeconds, 10)

        state.resume()
        state.tick()
        XCTAssertEqual(state.remainingSeconds, 9)
        XCTAssertEqual(state.phase, .running)
    }

    func testStartPauseResumeCompleteFlow() {
        let state = RestTimerState(duration: 4)
        var completionCalls = 0
        state.onComplete = { _ in completionCalls += 1 }

        // Simulate: start implicit (initial phase is .running).
        XCTAssertEqual(state.phase, .running)

        state.tick() // 3
        state.pause()
        XCTAssertEqual(state.phase, .paused)

        state.tick() // no-op (paused)
        XCTAssertEqual(state.remainingSeconds, 3)

        state.resume()
        state.tick() // 2
        state.tick() // 1
        state.tick() // 0 → complete
        XCTAssertEqual(state.phase, .complete)
        XCTAssertEqual(completionCalls, 1)
    }

    // MARK: - Double-complete protection

    func testSkipAfterNaturalCompletionDoesNotFireAgain() {
        let state = RestTimerState(duration: 1)
        var completionCalls = 0
        state.onComplete = { _ in completionCalls += 1 }

        state.tick() // 0 → natural complete
        XCTAssertEqual(completionCalls, 1)

        state.skip() // already complete — should be a no-op
        XCTAssertEqual(completionCalls, 1, "Skip after natural completion must not re-fire onComplete")
    }

    func testNaturalCompletionAfterSkipDoesNotFireAgain() {
        let state = RestTimerState(duration: 3)
        var completionCalls = 0
        state.onComplete = { _ in completionCalls += 1 }

        state.skip()
        XCTAssertEqual(completionCalls, 1)

        // Further ticks must not re-fire — phase is .complete.
        state.tick()
        state.tick()
        state.tick()
        XCTAssertEqual(completionCalls, 1)
    }

    func testSkipIsCalledWithNaturalFalse() {
        let state = RestTimerState(duration: 10)
        var natural: Bool?
        state.onComplete = { natural = $0 }
        state.skip()
        XCTAssertEqual(natural, false)
    }

    // MARK: - Warning haptic boundary

    func testWarningFiresOnceAtSixToFiveBoundary() {
        let state = RestTimerState(duration: 8)
        var warnings = 0
        state.onWarning = { warnings += 1 }

        state.tick() // 7
        state.tick() // 6
        XCTAssertEqual(warnings, 0, "No warning until we cross into 5s")
        state.tick() // 5
        XCTAssertEqual(warnings, 1, "Warning must fire exactly at 6→5 boundary")
        state.tick() // 4
        state.tick() // 3
        XCTAssertEqual(warnings, 1, "No re-fire below 5")
    }

    func testWarningDoesNotFireWhenTimerStartsBelowFiveSeconds() {
        let state = RestTimerState(duration: 3)
        var warnings = 0
        state.onWarning = { warnings += 1 }
        state.tick()
        state.tick()
        state.tick()
        XCTAssertEqual(warnings, 0)
    }

    // MARK: - Nudge

    func testNudgeAddsTime() {
        let state = RestTimerState(duration: 30)
        state.nudge(by: 30)
        XCTAssertEqual(state.remainingSeconds, 60)
    }

    func testNudgeSubtractsTime() {
        let state = RestTimerState(duration: 60)
        state.nudge(by: -15)
        XCTAssertEqual(state.remainingSeconds, 45)
    }

    func testNudgeFloorsAtOneSecond() {
        let state = RestTimerState(duration: 10)
        state.nudge(by: -100)
        XCTAssertEqual(state.remainingSeconds, 1, "Negative nudge must not complete the timer")
        XCTAssertNotEqual(state.phase, .complete)
    }

    func testNudgeOnCompleteIsNoOp() {
        let state = RestTimerState(duration: 1)
        state.tick() // complete
        state.nudge(by: 30)
        XCTAssertEqual(state.remainingSeconds, 0)
    }

    // MARK: - Progress

    func testProgressFillsFromZeroToOne() {
        let state = RestTimerState(duration: 4)
        XCTAssertEqual(state.progress, 0.0, accuracy: 0.0001)
        state.tick() // 3 remaining → 0.25
        XCTAssertEqual(state.progress, 0.25, accuracy: 0.0001)
        state.tick() // 2 → 0.5
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.0001)
        state.tick() // 1 → 0.75
        XCTAssertEqual(state.progress, 0.75, accuracy: 0.0001)
        state.tick() // 0 → 1.0
        XCTAssertEqual(state.progress, 1.0, accuracy: 0.0001)
    }

    // MARK: - Duration override mid-timer

    func testSetDurationResetsAndRestarts() {
        let state = RestTimerState(duration: 30)
        state.tick()
        state.tick()
        state.pause()

        state.setDuration(60)
        XCTAssertEqual(state.totalSeconds, 60)
        XCTAssertEqual(state.remainingSeconds, 60)
        XCTAssertEqual(state.phase, .running)
    }
}
