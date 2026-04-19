import XCTest
@testable import GearSnitch

@MainActor
final class ReferralViewModelTests: XCTestCase {

    // MARK: - Happy Path

    func testLoadReferralDataPopulatesStats() async {
        let service = FakeReferralService(result: .success(.sample(
            totalReferrals: 5,
            activeReferrals: 3,
            extensionDaysEarned: 84,
            history: [
                .rewarded(email: "alice@example.com"),
                .pending(email: "bob@example.com"),
            ]
        )))
        let vm = ReferralViewModel(service: service)

        await vm.loadReferralData()

        XCTAssertEqual(vm.data?.totalReferrals, 5)
        XCTAssertEqual(vm.data?.activeReferrals, 3)
        XCTAssertEqual(vm.pendingReferrals, 2,
                       "pending should equal total - accepted")
        XCTAssertEqual(vm.data?.extensionDaysEarned, 84)
        XCTAssertEqual(vm.data?.history.count, 2)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isEmpty)
    }

    func testPendingIsClampedAtZero() async {
        let service = FakeReferralService(result: .success(.sample(
            totalReferrals: 1,
            activeReferrals: 3, // backend briefly disagreeing
            extensionDaysEarned: 0,
            history: []
        )))
        let vm = ReferralViewModel(service: service)

        await vm.loadReferralData()

        XCTAssertEqual(vm.pendingReferrals, 0,
                       "pending must never be rendered as a negative number")
    }

    // MARK: - Empty State

    func testIsEmptyWhenHistoryIsEmpty() async {
        let service = FakeReferralService(result: .success(.sample(
            totalReferrals: 0,
            activeReferrals: 0,
            extensionDaysEarned: 0,
            history: []
        )))
        let vm = ReferralViewModel(service: service)

        await vm.loadReferralData()

        XCTAssertTrue(vm.isEmpty)
    }

    func testIsNotEmptyWhileLoading() {
        let service = FakeReferralService(result: .success(.sample()))
        let vm = ReferralViewModel(service: service)

        XCTAssertFalse(vm.isEmpty,
                       "isEmpty is only true once a successful fetch returns 0 rows")
    }

    // MARK: - Error Handling

    func testLoadStoresErrorAndClearsLoadingState() async {
        let service = FakeReferralService(result: .failure(TestError.boom))
        let vm = ReferralViewModel(service: service)

        await vm.loadReferralData()

        XCTAssertNil(vm.data)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isEmpty,
                       "isEmpty must stay false while error is present so the UI shows the retry card, not the empty state")
    }

    // MARK: - Pull-to-refresh

    func testRefreshKeepsPreviousDataOnError() async {
        let initial = ReferralDataDTO.sample(
            totalReferrals: 2,
            activeReferrals: 1,
            extensionDaysEarned: 28,
            history: [.rewarded(email: "alice@example.com")]
        )
        let service = FakeReferralService(result: .success(initial))
        let vm = ReferralViewModel(service: service)
        await vm.loadReferralData()
        XCTAssertEqual(vm.data?.totalReferrals, 2)

        // Simulate a subsequent failed refresh.
        service.result = .failure(TestError.boom)
        await vm.refresh()

        XCTAssertEqual(vm.data?.totalReferrals, 2,
                       "refresh must not wipe cached history when the retry fails")
        XCTAssertNotNil(vm.error)
    }

    func testRefreshReplacesDataOnSuccess() async {
        let first = ReferralDataDTO.sample(totalReferrals: 1, activeReferrals: 0)
        let second = ReferralDataDTO.sample(totalReferrals: 4, activeReferrals: 2)
        let service = FakeReferralService(result: .success(first))
        let vm = ReferralViewModel(service: service)
        await vm.loadReferralData()
        XCTAssertEqual(vm.data?.totalReferrals, 1)

        service.result = .success(second)
        await vm.refresh()

        XCTAssertEqual(vm.data?.totalReferrals, 4)
        XCTAssertEqual(vm.data?.activeReferrals, 2)
        XCTAssertNil(vm.error)
    }

    // MARK: - History Item Formatting

    func testHistoryItemMasksEmailAddress() {
        XCTAssertEqual(
            ReferralInviteeFormatter.displayName(for: "shawn@geargrind.net"),
            "sh***@geargrind.net"
        )
        XCTAssertEqual(
            ReferralInviteeFormatter.displayName(for: "ab@example.com"),
            "a*@example.com"
        )
        XCTAssertEqual(
            ReferralInviteeFormatter.displayName(for: "x@example.com"),
            "x@example.com"
        )
    }

    func testHistoryItemFallsBackToAnonymousWhenEmailMissing() {
        XCTAssertEqual(
            ReferralInviteeFormatter.displayName(for: nil),
            "Anonymous"
        )
        XCTAssertEqual(
            ReferralInviteeFormatter.displayName(for: "   "),
            "Anonymous"
        )
        XCTAssertEqual(
            ReferralInviteeFormatter.displayName(for: "not-an-email"),
            "Anonymous"
        )
    }

    func testHasRewardReflectsBackendRewardDays() {
        let rewarded = ReferralHistoryItem.rewarded(email: "a@example.com")
        let pending = ReferralHistoryItem.pending(email: "b@example.com")

        XCTAssertTrue(rewarded.hasReward)
        XCTAssertFalse(pending.hasReward)
    }
}

// MARK: - Test Doubles

@MainActor
final class FakeReferralService: ReferralServicing {
    var result: Result<ReferralDataDTO, Error>
    private(set) var fetchCount = 0

    init(result: Result<ReferralDataDTO, Error>) {
        self.result = result
    }

    func fetchReferralData() async throws -> ReferralDataDTO {
        fetchCount += 1
        return try result.get()
    }
}

private enum TestError: Error {
    case boom
}

// MARK: - DTO Builders

private extension ReferralDataDTO {
    static func sample(
        referralCode: String = "ABC123",
        referralURL: String = "https://gearsnitch.com/ref/ABC123",
        totalReferrals: Int = 0,
        activeReferrals: Int = 0,
        extensionDaysEarned: Int = 0,
        history: [ReferralHistoryItem] = []
    ) -> ReferralDataDTO {
        ReferralDataDTO(
            referralCode: referralCode,
            referralURL: referralURL,
            totalReferrals: totalReferrals,
            activeReferrals: activeReferrals,
            extensionDaysEarned: extensionDaysEarned,
            history: history
        )
    }
}

private extension ReferralHistoryItem {
    static func rewarded(email: String) -> ReferralHistoryItem {
        ReferralHistoryItem(
            id: UUID().uuidString,
            referredEmail: email,
            status: "completed",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            rewardDays: 28,
            rewardedAt: Date(timeIntervalSince1970: 1_700_500_000),
            reason: nil
        )
    }

    static func pending(email: String) -> ReferralHistoryItem {
        ReferralHistoryItem(
            id: UUID().uuidString,
            referredEmail: email,
            status: "pending",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            rewardDays: nil,
            rewardedAt: nil,
            reason: "Awaiting qualifying subscription"
        )
    }
}
