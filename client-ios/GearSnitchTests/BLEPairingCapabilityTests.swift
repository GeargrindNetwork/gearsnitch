import XCTest
import CoreBluetooth
@testable import GearSnitch

@MainActor
final class BLEPairingCapabilityTests: XCTestCase {

    // MARK: - Capability Gate

    func testResolvesToLegacyOnIOS17() {
        let capability = BLEPairingCapability.resolve(
            iosMajor: 17,
            iosMinor: 0,
            accessorySessionSupported: true
        )
        XCTAssertEqual(capability, .legacyCoreBluetooth)
    }

    func testResolvesToLegacyOnIOS25() {
        let capability = BLEPairingCapability.resolve(
            iosMajor: 25,
            iosMinor: 9,
            accessorySessionSupported: true
        )
        XCTAssertEqual(capability, .legacyCoreBluetooth)
    }

    func testResolvesToLegacyOnIOS26_2() {
        // 26.2 is below the 26.3 floor where third-party ASKit was opened up.
        let capability = BLEPairingCapability.resolve(
            iosMajor: 26,
            iosMinor: 2,
            accessorySessionSupported: true
        )
        XCTAssertEqual(capability, .legacyCoreBluetooth)
    }

    func testResolvesToASKitOnIOS26_3() {
        let capability = BLEPairingCapability.resolve(
            iosMajor: 26,
            iosMinor: 3,
            accessorySessionSupported: true
        )
        XCTAssertEqual(capability, .accessorySetupKit)
    }

    func testResolvesToASKitOnIOS27() {
        let capability = BLEPairingCapability.resolve(
            iosMajor: 27,
            iosMinor: 0,
            accessorySessionSupported: true
        )
        XCTAssertEqual(capability, .accessorySetupKit)
    }

    func testResolvesToLegacyWhenSessionUnsupported() {
        // Even on supported OS, fall back if the runtime probe says no
        // (e.g. simulator without the proximity-pairing daemon).
        let capability = BLEPairingCapability.resolve(
            iosMajor: 26,
            iosMinor: 3,
            accessorySessionSupported: false
        )
        XCTAssertEqual(capability, .legacyCoreBluetooth)
    }

    // MARK: - Service-UUID Contract

    func testAccessorySetupKitSupportsAllStandardFitnessServices() {
        let supported = Set(AccessorySetupController.supportedServiceUUIDs)

        // These four are the GATT service UUIDs the legacy BLEScanner
        // already filters on. Any drift here would mean the new picker
        // would silently drop gear we used to support.
        let mustInclude: [CBUUID] = [
            CBUUID(string: "180D"), // Heart Rate
            CBUUID(string: "180F"), // Battery
            CBUUID(string: "1818"), // Cycling Power
            CBUUID(string: "1814"), // Running Speed
        ]

        for uuid in mustInclude {
            XCTAssertTrue(
                supported.contains(uuid),
                "AccessorySetupController missing service \(uuid.uuidString)"
            )
        }
    }

    func testAccessorySetupKitContractIsSupersetOfBLEManagerScanList() {
        // The picker must accept everything the legacy scanner accepts,
        // otherwise on-OS upgrade we'd start filtering out previously
        // visible gear.
        let pickerSet = Set(AccessorySetupController.contractServiceUUIDsForLegacyParity)
        let scanSet = Set(BLEManager.registeredServiceUUIDs)

        let missing = scanSet.subtracting(pickerSet)
        XCTAssertTrue(
            missing.isEmpty,
            "Picker is missing services scanned by BLEManager: \(missing.map(\.uuidString))"
        )
    }

    func testAccessorySetupControllerSupportedServiceUUIDsAreSorted() {
        let uuids = AccessorySetupController.supportedServiceUUIDs
        let sorted = uuids.sorted { $0.uuidString < $1.uuidString }
        XCTAssertEqual(uuids, sorted, "supportedServiceUUIDs should be deterministically ordered")
    }

    func testAccessorySetupControllerSupportedServiceUUIDsAreUnique() {
        let uuids = AccessorySetupController.supportedServiceUUIDs
        XCTAssertEqual(
            uuids.count,
            Set(uuids).count,
            "supportedServiceUUIDs must not contain duplicates"
        )
    }
}
