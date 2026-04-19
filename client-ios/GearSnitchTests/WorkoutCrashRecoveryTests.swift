import HealthKit
import XCTest
@testable import GearSnitch

/// Tests for the crash-recovery plumbing introduced by backlog item #10.
///
/// We can't construct a real `HKWorkoutSession` in a unit-test target (that
/// requires real HealthKit entitlements and a live healthstore), so the
/// tests focus on the handoff surface between the scene delegate and the
/// viewmodel:
///
///   * `RecoveredWorkoutStore` is a thread-safe one-shot box.
///   * `WorkoutLiveActivityAttributes.ContentState` encodes round-trips.
///   * `WorkoutRecoveryToast` has a stable shape so the view can diff on it.
final class WorkoutCrashRecoveryTests: XCTestCase {

    // MARK: - RecoveredWorkoutStore

    func testRecoveredSessionStore_storeAndConsume() {
        let store = RecoveredWorkoutStore()
        XCTAssertFalse(store.hasPendingSession)

        let sentinel = NSObject()
        store.store(sentinel)
        XCTAssertTrue(store.hasPendingSession)

        let consumed = store.consume()
        XCTAssertTrue(consumed === sentinel)
        XCTAssertFalse(store.hasPendingSession, "consume() must clear the slot")
    }

    func testRecoveredSessionStore_secondStoreOverwritesFirst() {
        let store = RecoveredWorkoutStore()
        let first = NSObject()
        let second = NSObject()

        store.store(first)
        store.store(second)

        let consumed = store.consume()
        XCTAssertTrue(consumed === second, "most recent recovered session must win")
    }

    func testRecoveredSessionStore_consumeOnEmptyReturnsNil() {
        let store = RecoveredWorkoutStore()
        XCTAssertNil(store.consume())
    }

    // MARK: - WorkoutRecoveryToast

    func testWorkoutRecoveryToastEquatable() {
        let date = Date()
        let toastA = WorkoutRecoveryToast(message: "hello", startedAt: date)
        let toastB = WorkoutRecoveryToast(message: "hello", startedAt: date)
        XCTAssertEqual(toastA, toastB)
    }

    // MARK: - Live Activity attributes round-trip

    func testWorkoutLiveActivityContentStateEncodes() throws {
        let state = WorkoutLiveActivityAttributes.ContentState(
            currentBPM: 142,
            heartRateZone: "cardio",
            elapsedSeconds: 830,
            distanceMeters: 2500,
            isActive: true
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            WorkoutLiveActivityAttributes.ContentState.self,
            from: data
        )

        XCTAssertEqual(decoded.currentBPM, 142)
        XCTAssertEqual(decoded.heartRateZone, "cardio")
        XCTAssertEqual(decoded.elapsedSeconds, 830)
        XCTAssertEqual(decoded.distanceMeters, 2500)
        XCTAssertTrue(decoded.isActive)
    }

    func testWorkoutLiveActivityContentStateEncodesNils() throws {
        let state = WorkoutLiveActivityAttributes.ContentState(
            currentBPM: nil,
            heartRateZone: nil,
            elapsedSeconds: 0,
            distanceMeters: nil,
            isActive: true
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            WorkoutLiveActivityAttributes.ContentState.self,
            from: data
        )

        XCTAssertNil(decoded.currentBPM)
        XCTAssertNil(decoded.heartRateZone)
        XCTAssertNil(decoded.distanceMeters)
        XCTAssertEqual(decoded.elapsedSeconds, 0)
        XCTAssertTrue(decoded.isActive)
    }

    // MARK: - ActiveWorkoutSnapshot

    @available(iOS 26.0, *)
    func testActiveWorkoutSnapshotEquality() {
        let now = Date()
        let a = ActiveWorkoutSnapshot(
            activityType: .running,
            startedAt: now,
            elapsedSeconds: 600,
            currentBPM: 140,
            totalEnergyKcal: 50,
            totalDistanceMeters: 1500,
            state: .running
        )
        let b = ActiveWorkoutSnapshot(
            activityType: .running,
            startedAt: now,
            elapsedSeconds: 600,
            currentBPM: 140,
            totalEnergyKcal: 50,
            totalDistanceMeters: 1500,
            state: .running
        )
        XCTAssertEqual(a, b)
    }
}
