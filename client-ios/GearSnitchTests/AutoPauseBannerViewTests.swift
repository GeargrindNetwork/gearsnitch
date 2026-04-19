import XCTest
import SwiftUI
@testable import GearSnitch

// MARK: - AutoPauseBannerViewTests (Backlog item #18)
//
// We don't use image-based snapshot libraries (no new deps). These
// tests pin the banner's copy + iconography so accidental changes
// are caught in CI — the banner's strings are part of the product
// surface.

@MainActor
final class AutoPauseBannerViewTests: XCTestCase {

    func testPausedTitle() {
        XCTAssertEqual(AutoPauseBannerView.title(for: .paused), "Auto-paused")
    }

    func testResumedTitle() {
        XCTAssertEqual(AutoPauseBannerView.title(for: .resumed), "Resumed")
    }

    func testPausedSubtitleMentionsFrozen() {
        XCTAssertTrue(
            AutoPauseBannerView.subtitle(for: .paused).lowercased().contains("frozen"),
            "Paused banner should explain the timer is frozen."
        )
    }

    func testResumedSubtitle() {
        XCTAssertEqual(AutoPauseBannerView.subtitle(for: .resumed), "Tracking is back on.")
    }

    func testSystemIcons() {
        XCTAssertEqual(AutoPauseBannerView.systemImageName(for: .paused), "pause.circle.fill")
        XCTAssertEqual(AutoPauseBannerView.systemImageName(for: .resumed), "play.circle.fill")
    }

    func testAccessibilityLabelIncludesTitleAndSubtitle() {
        let label = AutoPauseBannerView.accessibilityLabel(for: .paused)
        XCTAssertTrue(label.contains("Auto-paused"))
        XCTAssertTrue(label.lowercased().contains("frozen"))
    }

    func testBannerCanBeConstructed() {
        // Ensures the view initializer still compiles against the
        // current RunTrackingManager.AutoPauseBannerState enum.
        let view = AutoPauseBannerView(state: .paused)
        XCTAssertNotNil(view.body)
    }
}
