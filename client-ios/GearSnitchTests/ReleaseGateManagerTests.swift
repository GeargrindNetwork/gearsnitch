import XCTest
@testable import GearSnitch

@MainActor
final class ReleaseGateManagerTests: XCTestCase {

    func testEvaluateCompatibilityBlocksWhenInstalledVersionIsBelowMinimum() {
        let release = ReleaseConfig(
            minimumVersion: "1.1.0",
            currentVersion: "1.2.0",
            forceUpdate: true,
            releaseNotes: ["Critical compatibility update"],
            publishedAt: "2026-04-12T00:00:00.000Z"
        )

        let blockedState = ReleaseGateManager.evaluateCompatibility(
            installedVersion: "1.0.0",
            release: release,
            compatibility: nil,
            serverVersion: "1.2.0"
        )

        XCTAssertNotNil(blockedState)
        XCTAssertEqual(blockedState?.requiredVersion, "1.1.0")
        XCTAssertEqual(blockedState?.serverVersion, "1.2.0")
    }

    func testEvaluateCompatibilityAllowsMatchingMinimumVersion() {
        let release = ReleaseConfig(
            minimumVersion: "1.1.0",
            currentVersion: "1.1.0",
            forceUpdate: false,
            releaseNotes: ["Launch-ready release"],
            publishedAt: "2026-04-12T00:00:00.000Z"
        )

        let blockedState = ReleaseGateManager.evaluateCompatibility(
            installedVersion: "1.1.0",
            release: release,
            compatibility: nil,
            serverVersion: "1.1.0"
        )

        XCTAssertNil(blockedState)
    }

    func testEvaluateCompatibilityHonorsBlockedServerCompatibility() {
        let release = ReleaseConfig(
            minimumVersion: "1.0.0",
            currentVersion: "1.2.0",
            forceUpdate: true,
            releaseNotes: ["Hard block old builds"],
            publishedAt: "2026-04-12T00:00:00.000Z"
        )
        let compatibility = CompatibilityConfig(
            status: "blocked",
            reason: "below_minimum_supported_version",
            clientVersion: "1.0.5",
            minimumSupportedVersion: "1.2.0",
            currentVersion: "1.2.0",
            forceUpgrade: true,
            platform: "ios",
            build: "3"
        )

        let blockedState = ReleaseGateManager.evaluateCompatibility(
            installedVersion: "1.0.5",
            release: release,
            compatibility: compatibility,
            serverVersion: "1.2.0"
        )

        XCTAssertEqual(blockedState?.requiredVersion, "1.2.0")
        XCTAssertEqual(blockedState?.installedVersion, "1.0.5")
    }
}
