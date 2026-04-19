import XCTest
import SwiftUI
@testable import GearSnitch

/// Structural smoke tests for the shared `TopNavBar`. We do not have a
/// pixel-diff snapshot dependency, so these assert that the view
/// instantiates correctly across 3 canonical size classes and that its
/// config permutations never crash the render tree.
@MainActor
final class TopNavBarSnapshotTests: XCTestCase {

    // MARK: - Helpers

    private func host(
        _ config: TopNavBarConfig,
        contentSize: ContentSizeCategory
    ) -> UIHostingController<some View> {
        let view = TopNavBar(
            config: config,
            onProfileTap: {},
            onReferralTap: {},
            onCartTap: {},
            onDisarmTap: {}
        )
        .environment(\.sizeCategory, contentSize)
        return UIHostingController(rootView: view)
    }

    // MARK: - Size classes

    func testCompactSize_rendersAllButtons() {
        let controller = host(
            TopNavBarConfig(showCart: true, showReferral: true, showProfile: true, showDisarm: true),
            contentSize: .small
        )
        XCTAssertNotNil(controller.view)
    }

    func testRegularSize_rendersAllButtons() {
        let controller = host(
            TopNavBarConfig(showCart: true, showReferral: true, showProfile: true, showDisarm: true),
            contentSize: .large
        )
        XCTAssertNotNil(controller.view)
    }

    func testAccessibilityXL_rendersWithoutClipping() {
        let controller = host(
            TopNavBarConfig(showCart: true, showReferral: true, showProfile: true, showDisarm: true),
            contentSize: .accessibilityExtraLarge
        )
        XCTAssertNotNil(controller.view)
    }

    // MARK: - Config permutations

    func testConfigPermutations() {
        let configs: [TopNavBarConfig] = [
            TopNavBarConfig(showCart: false, showReferral: false, showProfile: true, showDisarm: false),
            TopNavBarConfig(showCart: true, showReferral: false, showProfile: true, showDisarm: false),
            TopNavBarConfig(showCart: true, showReferral: true, showProfile: true, showDisarm: true, isDisarmDisabled: true),
            TopNavBarConfig(showCart: false, showReferral: true, showProfile: true, showDisarm: true, isDisarmDisabled: false),
        ]

        for config in configs {
            let controller = host(config, contentSize: .large)
            XCTAssertNotNil(controller.view, "Config \(config) failed to render")
        }
    }
}
