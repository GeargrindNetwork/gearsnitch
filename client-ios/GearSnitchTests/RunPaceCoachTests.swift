import XCTest
@testable import GearSnitch

// MARK: - RunPaceCoachTests (Backlog item #21)
//
// Pure-logic tests for the pace-coach decision engine. The engine is
// frame-agnostic: we inject `now` so the 30s haptic cooldown doesn't
// require an actual wall-clock wait.

final class RunPaceCoachTests: XCTestCase {

    private let targetPace = 9 * 60           // 9:00 /mi
    private let drift: Double = 0.05          // ±5%

    // MARK: - Status bucketing

    func testOnPaceAtExactTarget() {
        let coach = RunPaceCoach()
        let decision = coach.evaluate(
            currentPaceSecondsPerMile: targetPace,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift
        )
        XCTAssertEqual(decision.status, .onPace)
        XCTAssertNil(decision.haptic)
    }

    func testSpeedUpWhenTooSlow() {
        // Current pace is 9:30, target is 9:00 — they're running slower
        // than target (bigger sec/mile), so the coach should tell them
        // to speed up and fire directionUp.
        let coach = RunPaceCoach()
        let decision = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift
        )
        XCTAssertEqual(decision.status, .speedUp)
        XCTAssertEqual(decision.haptic, .directionUp)
    }

    func testSlowDownWhenTooFast() {
        // Current pace is 8:30, target is 9:00 — they're faster than
        // target (smaller sec/mile), so the coach should tell them to
        // slow down and fire directionDown.
        let coach = RunPaceCoach()
        let decision = coach.evaluate(
            currentPaceSecondsPerMile: 8 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift
        )
        XCTAssertEqual(decision.status, .slowDown)
        XCTAssertEqual(decision.haptic, .directionDown)
    }

    func testOnPaceWithinThreshold() {
        // 9:15 vs 9:00 — ratio = 555/540 ≈ 1.028, inside ±5% band.
        let coach = RunPaceCoach()
        let decision = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 15,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift
        )
        XCTAssertEqual(decision.status, .onPace)
        XCTAssertNil(decision.haptic)
    }

    func testThresholdBoundaryIsInclusive() {
        // Exactly at 1 + drift = 1.05 → ratio stays inside the band
        // (we use strict > for the off-pace flip).
        let current = Int(Double(targetPace) * 1.05)
        let coach = RunPaceCoach()
        let decision = coach.evaluate(
            currentPaceSecondsPerMile: current,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift
        )
        XCTAssertEqual(decision.status, .onPace)
    }

    // MARK: - Nil / zero handling

    func testNilCurrentPaceReturnsOnPaceWithNoHaptic() {
        let coach = RunPaceCoach()
        let decision = coach.evaluate(
            currentPaceSecondsPerMile: nil,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift
        )
        XCTAssertEqual(decision.status, .onPace)
        XCTAssertNil(decision.haptic)
    }

    func testZeroTargetPaceIsSafe() {
        let coach = RunPaceCoach()
        let decision = coach.evaluate(
            currentPaceSecondsPerMile: 540,
            targetPaceSecondsPerMile: 0,
            driftThresholdPct: drift
        )
        XCTAssertEqual(decision.status, .onPace)
        XCTAssertNil(decision.haptic)
    }

    // MARK: - Haptic throttling

    func testHapticSuppressedWithinCooldown() {
        let coach = RunPaceCoach(hapticCooldown: 30)
        let start = Date()

        let first = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift,
            now: start
        )
        XCTAssertEqual(first.haptic, .directionUp)

        // 10 seconds later — still within 30s cooldown.
        let second = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift,
            now: start.addingTimeInterval(10)
        )
        XCTAssertEqual(second.status, .speedUp, "Chip must still reflect off-pace reality")
        XCTAssertNil(second.haptic, "Haptic must be suppressed within cooldown")
    }

    func testHapticFiresAgainAfterCooldown() {
        let coach = RunPaceCoach(hapticCooldown: 30)
        let start = Date()

        _ = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift,
            now: start
        )

        let later = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift,
            now: start.addingTimeInterval(31)
        )
        XCTAssertEqual(later.haptic, .directionUp)
    }

    func testResetClearsCooldown() {
        let coach = RunPaceCoach(hapticCooldown: 30)
        let start = Date()

        _ = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift,
            now: start
        )
        XCTAssertNotNil(coach.lastHapticFiredAtForTesting)

        coach.reset()
        XCTAssertNil(coach.lastHapticFiredAtForTesting)

        // A fresh session immediately after a reset should fire.
        let afterReset = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift,
            now: start.addingTimeInterval(1)
        )
        XCTAssertEqual(afterReset.haptic, .directionUp)
    }

    func testOnPaceTickDoesNotConsumeCooldown() {
        // Evaluating an on-pace tick right after an off-pace haptic
        // must NOT move the cooldown window forward — otherwise a
        // runner who dips in/out of pace would never hear a second
        // buzz.
        let coach = RunPaceCoach(hapticCooldown: 30)
        let start = Date()

        _ = coach.evaluate(
            currentPaceSecondsPerMile: 9 * 60 + 30,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift,
            now: start
        )
        let firstFiredAt = coach.lastHapticFiredAtForTesting

        // Brief on-pace window.
        _ = coach.evaluate(
            currentPaceSecondsPerMile: targetPace,
            targetPaceSecondsPerMile: targetPace,
            driftThresholdPct: drift,
            now: start.addingTimeInterval(15)
        )

        XCTAssertEqual(coach.lastHapticFiredAtForTesting, firstFiredAt,
                       "On-pace ticks must not touch the cooldown timestamp")
    }
}
