import XCTest
@testable import GearSnitch

/// Verifies that concurrent calls to `AuthManager.refreshToken()` are
/// coalesced into a single HTTP refresh request.
///
/// Regression guard for the login race where multiple authed requests
/// (e.g. `/auth/me`, `/config/app`, `/subscriptions/validate-apple`) fire
/// at launch, all get 401 from stale access tokens, and each independently
/// triggers a refresh. Because refresh tokens are single-use on the server,
/// only the first concurrent refresh succeeds — the rest 401, and the old
/// retry-on-refresh-failure logic interpreted that as "session truly expired"
/// and wiped the just-minted valid tokens.
@MainActor
final class AuthManagerRefreshCoalescingTests: XCTestCase {

    // MARK: - Keychain Scratch Keys

    private let accessTokenKey = KeychainStore.Key.accessToken.rawValue
    private let refreshTokenKey = KeychainStore.Key.refreshToken.rawValue

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        // Seed an existing refresh token so `performRefresh()` has something
        // to swap. The value itself is opaque — our fake executor ignores it.
        try KeychainStore.shared.save("fake-refresh-token", forKey: refreshTokenKey)
        try KeychainStore.shared.save("fake-access-token-OLD", forKey: accessTokenKey)
    }

    override func tearDown() async throws {
        AuthManager.refreshExecutorOverride = nil
        try? KeychainStore.shared.delete(forKey: accessTokenKey)
        try? KeychainStore.shared.delete(forKey: refreshTokenKey)
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Five concurrent `refreshToken()` callers should hit the server exactly
    /// once and all receive the same new access token.
    func testConcurrentRefreshCallsAreCoalescedIntoSingleHTTPCall() async throws {
        let callCount = InvocationCounter()
        let newAccessToken = "fake-access-token-NEW"
        let newRefreshToken = "fake-refresh-token-ROTATED"

        AuthManager.refreshExecutorOverride = { _ in
            await callCount.increment()
            // Simulate the server round-trip so concurrent callers actually
            // overlap in time — without the sleep, the first caller can
            // finish before the next one even enters `refreshToken()`.
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return TokenPairResponse(
                accessToken: newAccessToken,
                refreshToken: newRefreshToken
            )
        }

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask { @MainActor in
                    try await AuthManager.shared.refreshToken()
                }
            }
            var collected: [String] = []
            for try await token in group {
                collected.append(token)
            }
            return collected
        }

        let invocations = await callCount.value
        XCTAssertEqual(
            invocations,
            1,
            "Expected exactly one refresh HTTP call, got \(invocations). Concurrent refreshes were NOT coalesced — the single-use refresh token would get replayed and session would be falsely expired."
        )
        XCTAssertEqual(tokens.count, 5, "All 5 callers should complete.")
        for token in tokens {
            XCTAssertEqual(
                token,
                newAccessToken,
                "All coalesced callers must receive the same new access token."
            )
        }

        // And the persisted tokens must reflect the rotated pair.
        XCTAssertEqual(TokenStore.shared.accessToken, newAccessToken)
        XCTAssertEqual(TokenStore.shared.refreshToken, newRefreshToken)
    }

    /// A second `refreshToken()` issued AFTER the first has completed must
    /// fire a fresh HTTP call (we only coalesce *in-flight* requests — we do
    /// NOT cache results).
    func testSequentialRefreshCallsAreNotCoalesced() async throws {
        let callCount = InvocationCounter()

        AuthManager.refreshExecutorOverride = { _ in
            await callCount.increment()
            return TokenPairResponse(
                accessToken: "access-\(await callCount.value)",
                refreshToken: "refresh-\(await callCount.value)"
            )
        }

        _ = try await AuthManager.shared.refreshToken()
        _ = try await AuthManager.shared.refreshToken()

        let invocations = await callCount.value
        XCTAssertEqual(
            invocations,
            2,
            "Sequential (non-concurrent) refresh calls should each hit the server. The coalescer must release the in-flight slot after completion."
        )
    }

    /// If the in-flight refresh fails, all concurrent waiters see the same
    /// failure — and the slot is released so the next refresh can succeed.
    func testConcurrentRefreshFailurePropagatesToAllWaitersAndReleasesSlot() async throws {
        let callCount = InvocationCounter()
        let firstCallFailed = expectation(description: "first HTTP call fails")

        AuthManager.refreshExecutorOverride = { _ in
            let n = await callCount.increment()
            try await Task.sleep(nanoseconds: 50_000_000)
            if n == 1 {
                firstCallFailed.fulfill()
                throw NetworkError.tokenRefreshFailed
            }
            return TokenPairResponse(
                accessToken: "recovered-access",
                refreshToken: "recovered-refresh"
            )
        }

        // Fire three concurrent refreshes; all should fail with the same error.
        let results = await withTaskGroup(of: Result<String, Error>.self) { group in
            for _ in 0..<3 {
                group.addTask { @MainActor in
                    do {
                        return .success(try await AuthManager.shared.refreshToken())
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<String, Error>] = []
            for await r in group {
                collected.append(r)
            }
            return collected
        }

        await fulfillment(of: [firstCallFailed], timeout: 2)

        XCTAssertEqual(results.count, 3)
        for r in results {
            switch r {
            case .success:
                XCTFail("Expected all concurrent waiters to fail while the in-flight refresh failed.")
            case .failure(let error):
                XCTAssertEqual(error as? NetworkError, .tokenRefreshFailed)
            }
        }
        let invocationsAfterFailure = await callCount.value
        XCTAssertEqual(
            invocationsAfterFailure,
            1,
            "All three concurrent failures must come from a single shared HTTP call."
        )

        // After the in-flight slot is released, a new refresh should succeed.
        let recovered = try await AuthManager.shared.refreshToken()
        XCTAssertEqual(recovered, "recovered-access")
        let total = await callCount.value
        XCTAssertEqual(total, 2, "A new call after failure must hit the server again.")
    }
}

// MARK: - Test Helpers

/// Actor-based counter safely usable from concurrent Swift tasks.
private actor InvocationCounter {
    private var count = 0

    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }

    var value: Int { count }
}
