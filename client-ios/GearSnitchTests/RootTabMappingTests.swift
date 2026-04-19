import XCTest
@testable import GearSnitch

/// Unit tests for the S2 3-tab nav mapping.
/// These tests are intentionally pure-logic — they assert the legacy→new
/// tab mapping, analytics continuity payload shape, and the PrimaryTab
/// metadata without touching UIKit / SwiftUI.
final class RootTabMappingTests: XCTestCase {

    // MARK: - PrimaryTab coverage

    func testPrimaryTabHasExactlyThreeCases() {
        // The whole point of S2 is "three tabs, not more". If someone adds
        // a 4th tab case without updating the PRD, this test should fail
        // and force the conversation.
        XCTAssertEqual(PrimaryTab.allCases.count, 3)
    }

    func testPrimaryTabRawValuesAreStableAnalyticsIds() {
        // These raw values are baked into analytics event payloads
        // (`tab_entered.tab_id`). Changing them breaks historical funnels.
        XCTAssertEqual(PrimaryTab.gear.rawValue, "gear")
        XCTAssertEqual(PrimaryTab.train.rawValue, "train")
        XCTAssertEqual(PrimaryTab.chemistry.rawValue, "chemistry")
    }

    func testPrimaryTabTitlesMatchPRD() {
        XCTAssertEqual(PrimaryTab.gear.title, "Gear")
        XCTAssertEqual(PrimaryTab.train.title, "Train")
        XCTAssertEqual(PrimaryTab.chemistry.title, "Chemistry")
    }

    func testPrimaryTabProvidesSystemImage() {
        for tab in PrimaryTab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty, "PrimaryTab.\(tab) missing systemImage")
        }
    }

    // MARK: - Legacy → New mapping

    func testLegacyDashboardMapsToGear() {
        XCTAssertEqual(PrimaryTab.fromLegacy(.dashboard), .gear)
    }

    func testLegacyWorkoutsMapsToTrain() {
        XCTAssertEqual(PrimaryTab.fromLegacy(.workouts), .train)
    }

    func testLegacyHealthMapsToChemistry() {
        XCTAssertEqual(PrimaryTab.fromLegacy(.health), .chemistry)
    }

    func testLegacyStoreAndProfileFallBackToGear() {
        // Store + Profile no longer have a primary-tab home. They live
        // inside the avatar menu (Profile/Subscription) and the Gear-tab
        // store card (Store). Deep-links that still target them should
        // land on Gear as a safe default rather than silently break.
        XCTAssertEqual(PrimaryTab.fromLegacy(.store), .gear)
        XCTAssertEqual(PrimaryTab.fromLegacy(.profile), .gear)
    }

    func testPrimaryTabLegacyEquivalentIsStableForDeepLinks() {
        // `AppCoordinator.selectedTab` is the pre-S2 deep-link target.
        // We mirror it from PrimaryTab → Tab so existing universal-link
        // routes keep working during the S2 transition.
        XCTAssertEqual(PrimaryTab.gear.legacyEquivalent, .dashboard)
        XCTAssertEqual(PrimaryTab.train.legacyEquivalent, .workouts)
        XCTAssertEqual(PrimaryTab.chemistry.legacyEquivalent, .health)
    }

    // MARK: - Round-trip integrity

    func testLegacyRoundTripForMappedTabs() {
        // Only the three "canonical" legacy tabs round-trip exactly. The
        // orphans (store/profile) intentionally collapse to .gear.
        let canonicalLegacy: [Tab] = [.dashboard, .workouts, .health]
        for legacy in canonicalLegacy {
            let primary = PrimaryTab.fromLegacy(legacy)
            XCTAssertEqual(primary.legacyEquivalent, legacy, "Round-trip failed for \(legacy)")
        }
    }

    // MARK: - Analytics payload

    func testTabEnteredEventName() {
        let event = AnalyticsEvent.tabEntered(newTabId: "gear", legacyTabId: "dashboard")
        XCTAssertEqual(event.name, "tab_entered")
    }

    func testTabEnteredPayloadIncludesBothIDsForContinuity() {
        // Per the S2 PRD "Analytics continuity: map old tab names → new
        // tab IDs in the event payload". We assert both ids are present.
        let event = AnalyticsEvent.tabEntered(newTabId: "train", legacyTabId: "workouts")
        let properties = event.properties
        XCTAssertEqual(properties["tab_id"] as? String, "train")
        XCTAssertEqual(properties["legacy_tab_id"] as? String, "workouts")
    }

    func testTabEnteredPayloadForAllPrimaryTabs() {
        for tab in PrimaryTab.allCases {
            let event = AnalyticsEvent.tabEntered(
                newTabId: tab.rawValue,
                legacyTabId: tab.legacyEquivalent.rawValue
            )
            let props = event.properties
            XCTAssertEqual(props["tab_id"] as? String, tab.rawValue)
            XCTAssertEqual(props["legacy_tab_id"] as? String, tab.legacyEquivalent.rawValue)
        }
    }
}
