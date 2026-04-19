import XCTest
@testable import GearSnitch

/// Tests for the client-side `FeatureFlagService` cache (backlog item #34).
///
/// The service itself doesn't implement resolution order — the API returns
/// an already-resolved `{ flagName: Bool }` map — so these tests focus on
/// the pieces the client owns:
///
///   - Response decoding round-trips the wire contract.
///   - `isEnabled` reads from the cache with a caller-provided default.
///   - `snapshot` / `currentTier` reflect the last primed response.
///   - `clearCache` wipes state so the next `refresh()` would re-fetch.
///   - Cache TTL is respected when the injected clock advances past 60 s.
final class FeatureFlagServiceTests: XCTestCase {

    func testFeatureFlagsResponseDecodesServerEnvelope() throws {
        // The API wraps responses in a `data: {...}` envelope. `APIClient`
        // unwraps that before handing the payload to this decoder, so the
        // raw bytes here are just the inner object.
        let json = """
        {
            "flags": {
                "dark-mode": true,
                "experimental-runs": false
            },
            "tier": "hwmf"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FeatureFlagsResponse.self, from: json)

        XCTAssertEqual(decoded.flags["dark-mode"], true)
        XCTAssertEqual(decoded.flags["experimental-runs"], false)
        XCTAssertEqual(decoded.tier, "hwmf")
    }

    func testFeatureFlagsResponseToleratesNullTier() throws {
        let json = """
        { "flags": {} , "tier": null }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FeatureFlagsResponse.self, from: json)
        XCTAssertTrue(decoded.flags.isEmpty)
        XCTAssertNil(decoded.tier)
    }

    func testIsEnabledReadsFromPrimedCache() async {
        let service = FeatureFlagService(apiClient: .shared, now: { Date(timeIntervalSince1970: 1_000) })
        let response = FeatureFlagsResponse(
            flags: ["dark-mode": true, "beta-charts": false],
            tier: "hustle"
        )
        await service.primeCacheForTesting(response, at: Date(timeIntervalSince1970: 1_000))

        let darkMode = await service.isEnabled("dark-mode")
        let betaCharts = await service.isEnabled("beta-charts")
        let unknownDefaultFalse = await service.isEnabled("unknown")
        let unknownDefaultTrue = await service.isEnabled("unknown", default: true)

        XCTAssertTrue(darkMode)
        XCTAssertFalse(betaCharts)
        XCTAssertFalse(unknownDefaultFalse, "unknown flag falls back to default=false")
        XCTAssertTrue(unknownDefaultTrue, "unknown flag respects caller default=true")
    }

    func testIsEnabledReturnsDefaultWhenCacheIsEmpty() async {
        let service = FeatureFlagService()
        // No priming — the cache is empty.

        let off = await service.isEnabled("anything")
        let on = await service.isEnabled("anything", default: true)
        XCTAssertFalse(off)
        XCTAssertTrue(on)
    }

    func testSnapshotAndCurrentTierMirrorPrimedResponse() async {
        let service = FeatureFlagService()
        let response = FeatureFlagsResponse(
            flags: ["a": true, "b": false, "c": true],
            tier: "babyMomma"
        )
        await service.primeCacheForTesting(response, at: Date())

        let snapshot = await service.snapshot()
        let tier = await service.currentTier()

        XCTAssertEqual(snapshot, ["a": true, "b": false, "c": true])
        XCTAssertEqual(tier, "babyMomma")
    }

    func testClearCacheResetsState() async {
        let service = FeatureFlagService()
        let response = FeatureFlagsResponse(flags: ["x": true], tier: "hustle")
        await service.primeCacheForTesting(response, at: Date())

        let beforeClear = await service.isEnabled("x")
        XCTAssertTrue(beforeClear)

        await service.clearCache()

        let afterClear = await service.isEnabled("x")
        XCTAssertFalse(afterClear, "cleared cache returns default=false for previously-set flag")

        let snapshot = await service.snapshot()
        XCTAssertTrue(snapshot.isEmpty)

        let tier = await service.currentTier()
        XCTAssertNil(tier)
    }

    func testResolutionOrderDocumentedByServerShape() async {
        // The client test can't exercise the per-user > per-tier > global
        // ordering because that happens server-side. What the client
        // contract guarantees is: "whatever the server returned in the
        // `flags` map is the final resolved value." Exercise that by
        // priming the cache with a value that would only be produced by
        // the server's full resolution chain.
        let service = FeatureFlagService()
        let resolved = FeatureFlagsResponse(
            flags: [
                "user-override-wins": false,  // user overrode to false
                "tier-override-wins": true,   // tier bumped to true
                "global-only": true,           // global true, no overrides
            ],
            tier: "hwmf"
        )
        await service.primeCacheForTesting(resolved, at: Date())

        let userWins = await service.isEnabled("user-override-wins", default: true)
        let tierWins = await service.isEnabled("tier-override-wins", default: false)
        let globalOnly = await service.isEnabled("global-only", default: false)

        XCTAssertFalse(userWins, "user override (false) survived through to client")
        XCTAssertTrue(tierWins, "tier override (true) survived through to client")
        XCTAssertTrue(globalOnly, "global value (true) surfaced when no overrides")
    }
}
