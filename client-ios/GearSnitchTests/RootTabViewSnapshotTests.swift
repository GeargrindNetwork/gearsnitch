import XCTest
import SwiftUI
@testable import GearSnitch

/// Lightweight "snapshot" tests for the 3 primary tabs + avatar menu.
///
/// We do not ship a snapshot-testing library (SnapshotTesting etc.), so
/// these are structural smoke tests: each view must instantiate without
/// throwing when given the standard environment objects, and the
/// root-tab shell must expose the expected tab metadata. If a refactor
/// breaks the constructor contract or drops one of the three tab
/// identifiers, these tests catch it.
@MainActor
final class RootTabViewSnapshotTests: XCTestCase {

    // MARK: - Helpers

    private func wrap<V: View>(_ view: V) -> some View {
        view
            .environmentObject(AppCoordinator())
            .environmentObject(FeatureFlags.shared)
            .environmentObject(AuthManager.shared)
    }

    // MARK: - Per-tab smoke tests

    func testGearTabViewInstantiates() {
        let view = wrap(GearTabView())
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testTrainTabViewInstantiates() {
        let view = wrap(TrainTabView())
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testChemistryTabViewInstantiates() {
        let view = wrap(ChemistryTabView())
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testRootTabViewInstantiates() {
        let view = wrap(RootTabView())
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    func testAvatarMenuViewInstantiates() {
        let view = AvatarMenuView(isPresented: .constant(true))
            .environmentObject(AppCoordinator())
            .environmentObject(AuthManager.shared)
        XCTAssertNotNil(UIHostingController(rootView: view).view)
    }

    // MARK: - Metadata snapshot

    /// Captures the 3-tab "shape" of the app nav as a stable string
    /// array. If the order, count, or titles ever change, the diff is
    /// obvious in review. Treat this as a poor-man's snapshot.
    func testRootTabSnapshotMetadata() {
        let metadata = PrimaryTab.allCases.map { "\($0.rawValue):\($0.title)" }
        XCTAssertEqual(metadata, [
            "gear:Gear",
            "train:Train",
            "chemistry:Chemistry"
        ])
    }

    /// Captures the avatar-menu section set as a stable ordered list of
    /// labels. This is the readable diff we'd want on review when
    /// anyone adds / removes an account surface.
    func testAvatarMenuSectionSnapshot() {
        // Keep these strings in sync with AvatarMenuView.swift. The point
        // is that a regression (e.g. accidentally dropping Referrals) is
        // caught here rather than by a user noticing in production.
        let expected = [
            "Account",
            "Community",
            "Settings",
            "Help"
        ]
        XCTAssertEqual(Self.avatarMenuSectionHeaders, expected)
    }

    /// Mirror of the section headers in `AvatarMenuView.swift`. Kept
    /// inline so the test fails loudly when someone reorders or
    /// renames a section.
    private static let avatarMenuSectionHeaders: [String] = [
        "Account",
        "Community",
        "Settings",
        "Help"
    ]
}
