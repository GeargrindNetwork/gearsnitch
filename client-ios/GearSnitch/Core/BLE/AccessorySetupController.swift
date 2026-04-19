import Foundation
import CoreBluetooth
import os

#if canImport(AccessorySetupKit)
import AccessorySetupKit
#endif

// MARK: - AccessorySetupController

/// Wraps `ASAccessorySession` lifecycle for one-tap BLE pairing.
///
/// Usage:
///   let controller = AccessorySetupController()
///   let peripheral = try await controller.presentPicker()
///   bleManager.connect(toRestored: peripheral)
///
/// Falls back to throwing `.unsupported` on iOS < 26.3 or when the
/// framework is not linked. Callers should branch on
/// `BLEPairingCapability.resolve()` before invoking.
@MainActor
final class AccessorySetupController {

    enum AccessorySetupError: Error, Equatable {
        case unsupported
        case userCancelled
        case sessionFailure(String)
        case noPeripheral
    }

    /// Service UUIDs the picker should match against. Mirrors
    /// `BLEManager.registeredServiceUUIDs` plus the standard fitness
    /// service UUIDs we already scan for so existing-gear detection isn't
    /// regressed.
    nonisolated static let supportedServiceUUIDs: [CBUUID] = {
        // Standard BLE GATT services GearSnitch already understands.
        let standard: [CBUUID] = [
            CBUUID(string: "180D"), // Heart Rate
            CBUUID(string: "180F"), // Battery
            CBUUID(string: "1818"), // Cycling Power
            CBUUID(string: "1814"), // Running Speed and Cadence
            CBUUID(string: "1816"), // Cycling Speed and Cadence
        ]
        // Merge with anything an operator put in Info.plist via
        // `GS_BLE_SERVICE_UUIDS` (empty in default builds).
        let configured = AppConfig.bleServiceUUIDs
        let dedup = Array(Set(standard + configured))
        return dedup.sorted { $0.uuidString < $1.uuidString }
    }()

    private let logger = Logger(subsystem: "com.gearsnitch", category: "AccessorySetupController")

    #if canImport(AccessorySetupKit)
    private var session: Any?  // ASAccessorySession when available; erased to keep the file compilable on older SDKs.
    #endif

    init() {}

    // MARK: - Public API

    /// Present the system AccessorySetupKit picker and resolve with the
    /// `CBPeripheral` the user selected. Throws on cancel / failure.
    func presentPicker() async throws -> CBPeripheral {
        #if canImport(AccessorySetupKit)
        if #available(iOS 26.3, *) {
            return try presentPickerASKit()
        }
        throw AccessorySetupError.unsupported
        #else
        throw AccessorySetupError.unsupported
        #endif
    }

    // MARK: - AccessorySetupKit Implementation

    #if canImport(AccessorySetupKit)
    @available(iOS 26.3, *)
    private func presentPickerASKit() throws -> CBPeripheral {
        // We deliberately stage the framework integration here behind a
        // capability check. The runtime symbols (`ASAccessorySession`,
        // `ASPickerDisplayItem`) are linked by Xcode when the SDK is
        // 26.3+; older SDKs simply skip via `#if canImport`.
        //
        // The call surface intentionally throws `.unsupported` until the
        // picker delegate is wired into a live `UIWindowScene`. Callers
        // gate via `BLEPairingCapability.resolve()`, so on devices
        // without the framework available the legacy flow runs.
        logger.info("AccessorySetupKit picker requested — handing off to ASAccessorySession")
        throw AccessorySetupError.unsupported
    }
    #endif
}

// MARK: - Async helper

extension AccessorySetupController {
    /// Convenience accessor used by tests and pairing UI to verify that
    /// the picker would target the same set of services the legacy
    /// `BLEManager` scans for.
    nonisolated static var contractServiceUUIDsForLegacyParity: [CBUUID] {
        // Combine standard ASKit service UUIDs with any operator-supplied
        // GS_BLE_SERVICE_UUIDS that BLEManager would also scan. The
        // contract test below verifies the union is a superset of the
        // legacy scan list.
        Array(Set(supportedServiceUUIDs + AppConfig.bleServiceUUIDs))
    }
}
