import XCTest
@testable import GearSnitch

// MARK: - ReviewPromptControllerTests (Backlog item #26)
//
// Covers the threshold + cooldown + install-age gate for the App Store
// review prompt. All tests use a suite-backed `UserDefaults` so they
// never touch `.standard`, and inject a recording `ReviewPromptPresenter`
// so `SKStoreReviewController` is never actually called.

@MainActor
final class ReviewPromptControllerTests: XCTestCase {

    // MARK: - Recording presenter

    private final class RecordingPresenter: ReviewPromptPresenter {
        var requestCount = 0
        func requestReview() {
            requestCount += 1
        }
    }

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var presenter: RecordingPresenter!

    override func setUp() {
        super.setUp()
        suiteName = "com.gearsnitch.tests.reviewPrompt.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        presenter = RecordingPresenter()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        presenter = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Build a controller with its `now` clock frozen at `clock`, and an
    /// install stamp already written `daysAgo` days earlier so each test
    /// can decouple install date from the current wall clock.
    private func makeController(
        clock: Date,
        daysSinceInstall: Int
    ) -> ReviewPromptController {
        let installDate = clock.addingTimeInterval(TimeInterval(-daysSinceInstall) * 86_400)
        defaults.set(installDate, forKey: ReviewPromptKey.installedAt)
        return ReviewPromptController(
            defaults: defaults,
            presenter: presenter,
            now: { clock }
        )
    }

    // MARK: - Counter increments

    func test_recordWorkoutCompleted_incrementsCounter() {
        let controller = makeController(clock: Date(), daysSinceInstall: 30)
        XCTAssertEqual(controller.completedWorkouts, 0)

        controller.recordWorkoutCompleted()
        controller.recordWorkoutCompleted()

        XCTAssertEqual(controller.completedWorkouts, 2)
    }

    func test_recordDevicePaired_incrementsCounter() {
        let controller = makeController(clock: Date(), daysSinceInstall: 30)
        controller.recordDevicePaired()
        controller.recordDevicePaired()
        controller.recordDevicePaired()
        XCTAssertEqual(controller.pairedDevices, 3)
    }

    func test_recordAppSessionStart_debouncesByTenMinutes() {
        var clock = Date()
        let controller = ReviewPromptController(
            defaults: defaults,
            presenter: presenter,
            now: { clock }
        )

        controller.recordAppSessionStart()
        XCTAssertEqual(controller.appSessions, 1)

        // Within the 10-minute debounce window — ignored.
        clock = clock.addingTimeInterval(5 * 60)
        controller.recordAppSessionStart()
        XCTAssertEqual(controller.appSessions, 1)

        // Past the debounce window — counted.
        clock = clock.addingTimeInterval(10 * 60)
        controller.recordAppSessionStart()
        XCTAssertEqual(controller.appSessions, 2)
    }

    // MARK: - Trigger gate

    func test_maybeRequestReview_doesNothing_belowWorkoutThreshold() {
        let controller = makeController(clock: Date(), daysSinceInstall: 30)
        controller.recordWorkoutCompleted()
        controller.recordWorkoutCompleted() // 2 → below 3
        controller.maybeRequestReview()

        XCTAssertEqual(presenter.requestCount, 0)
        XCTAssertNil(controller.lastPromptedAt)
    }

    func test_maybeRequestReview_doesNothing_beforeMinInstallAge() {
        // 3 workouts but only 13 days since install — must not prompt.
        let controller = makeController(clock: Date(), daysSinceInstall: 13)
        for _ in 0..<3 { controller.recordWorkoutCompleted() }

        controller.maybeRequestReview()

        XCTAssertEqual(presenter.requestCount, 0)
        XCTAssertNil(controller.lastPromptedAt)
    }

    func test_maybeRequestReview_prompts_afterThreeWorkoutsAndFourteenDays() {
        let controller = makeController(clock: Date(), daysSinceInstall: 14)
        for _ in 0..<3 { controller.recordWorkoutCompleted() }

        controller.maybeRequestReview()

        XCTAssertEqual(presenter.requestCount, 1)
        XCTAssertNotNil(controller.lastPromptedAt)
    }

    func test_maybeRequestReview_prompts_afterFiveDevicePairs() {
        let controller = makeController(clock: Date(), daysSinceInstall: 20)
        for _ in 0..<5 { controller.recordDevicePaired() }

        controller.maybeRequestReview()

        XCTAssertEqual(presenter.requestCount, 1)
    }

    func test_maybeRequestReview_prompts_afterSevenSessions() {
        // Build sessions manually so we don't have to walk the debounce
        // clock seven times.
        defaults.set(7, forKey: ReviewPromptKey.appSessions)
        let controller = makeController(clock: Date(), daysSinceInstall: 20)

        controller.maybeRequestReview()

        XCTAssertEqual(presenter.requestCount, 1)
    }

    // MARK: - Cooldown

    func test_maybeRequestReview_respectsThirtyDayCooldown() {
        let now = Date()
        let twentyDaysAgo = now.addingTimeInterval(-20 * 86_400)
        defaults.set(twentyDaysAgo, forKey: ReviewPromptKey.lastPromptedAt)

        let controller = makeController(clock: now, daysSinceInstall: 90)
        for _ in 0..<3 { controller.recordWorkoutCompleted() }

        controller.maybeRequestReview()

        XCTAssertEqual(presenter.requestCount, 0,
                       "Must not prompt again within 30 days of the last prompt")
        // Stored lastPromptedAt should be unchanged.
        XCTAssertEqual(
            (controller.lastPromptedAt ?? .distantPast).timeIntervalSince1970,
            twentyDaysAgo.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func test_maybeRequestReview_prompts_afterCooldownExpires() {
        let now = Date()
        let thirtyOneDaysAgo = now.addingTimeInterval(-31 * 86_400)
        defaults.set(thirtyOneDaysAgo, forKey: ReviewPromptKey.lastPromptedAt)

        let controller = makeController(clock: now, daysSinceInstall: 120)
        for _ in 0..<3 { controller.recordWorkoutCompleted() }

        controller.maybeRequestReview()

        XCTAssertEqual(presenter.requestCount, 1)
    }

    // MARK: - Corruption / reset

    func test_install_stampSetOnFirstLaunch_whenMissing() {
        // Fresh suite — install key not set. Controller should stamp.
        let clock = Date()
        let controller = ReviewPromptController(
            defaults: defaults,
            presenter: presenter,
            now: { clock }
        )

        XCTAssertNotNil(controller.installedAt)
        XCTAssertEqual(
            (controller.installedAt ?? .distantPast).timeIntervalSince1970,
            clock.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func test_negativeCounter_isTreatedAsZero() {
        // Simulate corrupted state: a negative counter. Increment must
        // coerce to 1, not -1 + 1 = 0 (which would hide work done).
        defaults.set(-5, forKey: ReviewPromptKey.completedWorkouts)
        let controller = makeController(clock: Date(), daysSinceInstall: 30)

        controller.recordWorkoutCompleted()

        XCTAssertEqual(controller.completedWorkouts, 1)
    }

    func test_shouldPrompt_falseWhenAllCountersZero() {
        let controller = makeController(clock: Date(), daysSinceInstall: 60)
        XCTAssertFalse(controller.shouldPrompt())
    }
}
