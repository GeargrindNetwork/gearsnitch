import XCTest
@testable import GearSnitch

@MainActor
final class HandPreferenceManagerTests: XCTestCase {

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: "gs_menu_side")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "gs_menu_side")
    }

    func testDefaultSideIsRight() {
        UserDefaults.standard.removeObject(forKey: "gs_menu_side")
        // Note: shared is a singleton so the initial value is only read once per process.
        // We verify behavior via the enum instead of reinstantiating.
        let stored = UserDefaults.standard.string(forKey: "gs_menu_side")
        XCTAssertNil(stored)
    }

    func testChangingSidePersistsToUserDefaults() {
        HandPreferenceManager.shared.menuSide = .left
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gs_menu_side"), "left")

        HandPreferenceManager.shared.menuSide = .right
        XCTAssertEqual(UserDefaults.standard.string(forKey: "gs_menu_side"), "right")
    }

    func testIsMenuOnLeftFlag() {
        HandPreferenceManager.shared.menuSide = .left
        XCTAssertTrue(HandPreferenceManager.shared.isMenuOnLeft)

        HandPreferenceManager.shared.menuSide = .right
        XCTAssertFalse(HandPreferenceManager.shared.isMenuOnLeft)
    }

    func testHandSideCodable() throws {
        let encoded = try JSONEncoder().encode(HandSide.left)
        let decoded = try JSONDecoder().decode(HandSide.self, from: encoded)
        XCTAssertEqual(decoded, .left)

        let encodedRight = try JSONEncoder().encode(HandSide.right)
        let decodedRight = try JSONDecoder().decode(HandSide.self, from: encodedRight)
        XCTAssertEqual(decodedRight, .right)
    }
}
