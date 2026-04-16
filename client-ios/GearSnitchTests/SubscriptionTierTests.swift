import XCTest
@testable import GearSnitch

final class SubscriptionTierTests: XCTestCase {

    func testUpgradeOrderIncreasesAcrossTiers() {
        XCTAssertLessThan(SubscriptionTier.hustle.upgradeOrder, SubscriptionTier.hwmf.upgradeOrder)
        XCTAssertLessThan(SubscriptionTier.hwmf.upgradeOrder, SubscriptionTier.babyMomma.upgradeOrder)
    }

    func testTierDisplayNames() {
        XCTAssertEqual(SubscriptionTier.hustle.displayName, "HUSTLE")
        XCTAssertEqual(SubscriptionTier.hwmf.displayName, "HWMF")
        XCTAssertEqual(SubscriptionTier.babyMomma.displayName, "BABY MOMMA")
    }

    func testTierProductIDs() {
        XCTAssertEqual(SubscriptionTier.hustle.productID, "com.gearsnitch.app.monthly")
        XCTAssertEqual(SubscriptionTier.hwmf.productID, "com.gearsnitch.app.annual")
        XCTAssertEqual(SubscriptionTier.babyMomma.productID, "com.gearsnitch.app.lifetime")
    }

    func testTierForProductIDResolvesCurrentAndLegacyIDs() {
        XCTAssertEqual(SubscriptionTier.tier(forProductID: "com.gearsnitch.app.monthly"), .hustle)
        XCTAssertEqual(SubscriptionTier.tier(forProductID: "com.geargrind.gearsnitch.monthly"), .hustle)
        XCTAssertEqual(SubscriptionTier.tier(forProductID: "com.gearsnitch.app.annual"), .hwmf)
        XCTAssertEqual(SubscriptionTier.tier(forProductID: "com.geargrind.gearsnitch.annual"), .hwmf)
        XCTAssertEqual(SubscriptionTier.tier(forProductID: "com.gearsnitch.app.lifetime"), .babyMomma)
        XCTAssertEqual(SubscriptionTier.tier(forProductID: "com.geargrind.gearsnitch.lifetime"), .babyMomma)
    }

    func testUnknownProductIDReturnsNil() {
        XCTAssertNil(SubscriptionTier.tier(forProductID: "com.unknown.product"))
    }

    func testHwmfHasRecommendedBadge() {
        XCTAssertEqual(SubscriptionTier.hwmf.badge, "Recommended")
    }

    func testBabyMommaHasBestValueBadge() {
        XCTAssertEqual(SubscriptionTier.babyMomma.badge, "Best Value")
    }

    func testHustleHasNoBadge() {
        XCTAssertNil(SubscriptionTier.hustle.badge)
    }
}
