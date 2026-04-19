import HealthKit
import XCTest
@testable import GearSnitch

/// Unit tests for the routing decision in `WorkoutSessionRouter`.
///
/// The router picks the transport for a new workout from three options:
///   1. Apple Watch (PRIMARY) — when a paired Watch is reachable.
///   2. iPhone HealthKit (FALLBACK) — iOS 26+ and workout auth granted.
///   3. Timer-only (LAST RESORT) — everything else.
///
/// These tests encode those priorities and — importantly — the guarantee
/// that the iPhone path never preempts an available Watch (Watch primacy
/// is a hard requirement in item #10's spec).
@MainActor
final class WorkoutSessionRouterTests: XCTestCase {

    // MARK: - Fakes

    final class FakeWatch: WatchReachabilityProviding {
        var isWatchPaired: Bool = false
        var isWatchReachable: Bool = false
    }

    final class FakeHealth: HealthKitAuthProviding {
        nonisolated(unsafe) static var isHealthDataAvailableOnDeviceValue: Bool = true
        static var isHealthDataAvailableOnDevice: Bool { isHealthDataAvailableOnDeviceValue }

        var workoutAuth: HKAuthorizationStatus = .notDetermined

        func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
            workoutAuth
        }
    }

    // MARK: - Watch primacy

    func testWatchPrimary_whenPairedAndReachable_returnsWatch() {
        let watch = FakeWatch()
        watch.isWatchPaired = true
        watch.isWatchReachable = true

        let health = FakeHealth()
        // Even with iPhone HK available and authorized, Watch still wins.
        health.workoutAuth = .sharingAuthorized

        let source = WorkoutSessionRouter.resolve(
            watch: watch,
            health: health,
            healthStoreType: FakeHealth.self,
            isIOS26OrLater: true
        )

        XCTAssertEqual(source, .watch, "Watch must take priority when paired + reachable")
    }

    func testWatchPrimary_whenPairedButUnreachable_fallsThroughToIPhone() {
        let watch = FakeWatch()
        watch.isWatchPaired = true
        watch.isWatchReachable = false

        let health = FakeHealth()
        health.workoutAuth = .sharingAuthorized

        let source = WorkoutSessionRouter.resolve(
            watch: watch,
            health: health,
            healthStoreType: FakeHealth.self,
            isIOS26OrLater: true
        )

        XCTAssertEqual(
            source, .iPhoneHealthKit,
            "Unreachable Watch must yield to iPhone-native HK (not block the workout)"
        )
    }

    // MARK: - iPhone fallback

    func testIPhoneFallback_onIOS26WithAuth_andNoWatch() {
        let watch = FakeWatch()
        watch.isWatchPaired = false

        let health = FakeHealth()
        health.workoutAuth = .sharingAuthorized

        let source = WorkoutSessionRouter.resolve(
            watch: watch,
            health: health,
            healthStoreType: FakeHealth.self,
            isIOS26OrLater: true
        )

        XCTAssertEqual(source, .iPhoneHealthKit)
    }

    func testIPhoneFallback_blockedOnOlderOS() {
        let watch = FakeWatch()
        let health = FakeHealth()
        health.workoutAuth = .sharingAuthorized

        let source = WorkoutSessionRouter.resolve(
            watch: watch,
            health: health,
            healthStoreType: FakeHealth.self,
            isIOS26OrLater: false
        )

        XCTAssertEqual(source, .timerOnly, "Pre-iOS-26 must fall all the way through")
    }

    func testIPhoneFallback_blockedWithoutAuth() {
        let watch = FakeWatch()
        let health = FakeHealth()
        health.workoutAuth = .notDetermined

        let source = WorkoutSessionRouter.resolve(
            watch: watch,
            health: health,
            healthStoreType: FakeHealth.self,
            isIOS26OrLater: true
        )

        XCTAssertEqual(source, .timerOnly)
    }

    func testIPhoneFallback_blockedIfHealthKitUnavailable() {
        let watch = FakeWatch()
        let health = FakeHealth()
        health.workoutAuth = .sharingAuthorized

        FakeHealth.isHealthDataAvailableOnDeviceValue = false
        defer { FakeHealth.isHealthDataAvailableOnDeviceValue = true }

        let source = WorkoutSessionRouter.resolve(
            watch: watch,
            health: health,
            healthStoreType: FakeHealth.self,
            isIOS26OrLater: true
        )

        XCTAssertEqual(source, .timerOnly)
    }

    // MARK: - Timer-only last resort

    func testTimerOnly_whenNothingAvailable() {
        let watch = FakeWatch()
        let health = FakeHealth()
        health.workoutAuth = .sharingDenied

        let source = WorkoutSessionRouter.resolve(
            watch: watch,
            health: health,
            healthStoreType: FakeHealth.self,
            isIOS26OrLater: true
        )

        XCTAssertEqual(source, .timerOnly)
    }

    // MARK: - Watch path is untouched when reachable

    /// Contract test: confirms that when the router picks `.watch`, the
    /// viewmodel's branch does NOT instantiate an iPhone-native session.
    /// This is the invariant that keeps Watch users on the Watch path.
    func testViewModelRoutingWatch_doesNotCreateIPhoneSession() {
        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(source: .watch)

        XCTAssertEqual(vm.workoutSource, .watch)
        XCTAssertTrue(vm.isActive)
        // No HK BPM because Watch path owns that; viewmodel stays clean.
        XCTAssertNil(vm.currentBPM)
    }

    func testViewModelRoutingTimerOnly_setsSourceTag() {
        let vm = ActiveWorkoutViewModel()
        vm.startWorkout(source: .timerOnly)

        XCTAssertEqual(vm.workoutSource, .timerOnly)
        XCTAssertEqual(vm.workoutSource.displayTag, "Powered by: Timer")
    }

    // MARK: - WorkoutSource display

    func testWorkoutSourceDisplayTags() {
        XCTAssertEqual(WorkoutSource.watch.displayTag, "Powered by: Apple Watch")
        XCTAssertEqual(WorkoutSource.iPhoneHealthKit.displayTag, "Powered by: iPhone HealthKit")
        XCTAssertEqual(WorkoutSource.timerOnly.displayTag, "Powered by: Timer")
    }
}
