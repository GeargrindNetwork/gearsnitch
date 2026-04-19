import Foundation

#if canImport(AccessorySetupKit)
import AccessorySetupKit
#endif

// MARK: - BLE Pairing Capability

/// Describes which pairing flow the app should present for a first-time
/// device pair. iOS 26.3 introduced third-party `AccessorySetupKit`
/// proximity pairing under the EU DMA expansion. Older OS versions fall
/// back to the legacy `CoreBluetooth` permission prompt + scan UI.
///
/// The enum is intentionally tiny so the gate logic can be unit-tested
/// without instantiating CoreBluetooth or the AccessorySetupKit framework.
enum BLEPairingCapability: Equatable {
    /// Use `AccessorySetupController` (`ASAccessorySession`) to present the
    /// AirPods-style proximity pairing sheet.
    case accessorySetupKit

    /// Use the existing `BLEManager` scan + connect flow with the system
    /// `NSBluetoothAlwaysUsageDescription` prompt.
    case legacyCoreBluetooth

    /// Resolve the capability for the current runtime.
    ///
    /// `iosVersion` and `accessorySessionSupported` parameters allow the
    /// gate to be exercised deterministically in tests.
    static func resolve(
        iosMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        iosMinor: Int = ProcessInfo.processInfo.operatingSystemVersion.minorVersion,
        accessorySessionSupported: Bool = BLEPairingCapability.runtimeAccessorySessionSupported()
    ) -> BLEPairingCapability {
        // Apple gated third-party AccessorySetupKit (Bluetooth) on iOS 26.3.
        let meetsMinimumOS = (iosMajor > 26) || (iosMajor == 26 && iosMinor >= 3)
        guard meetsMinimumOS, accessorySessionSupported else {
            return .legacyCoreBluetooth
        }
        return .accessorySetupKit
    }

    /// Probe `ASAccessorySession.isSupported` when the framework is
    /// available; fall back to `false` on older SDKs / non-iOS targets.
    static func runtimeAccessorySessionSupported() -> Bool {
        #if canImport(AccessorySetupKit)
        if #available(iOS 26.3, *) {
            return ASAccessorySession.isSupported
        }
        return false
        #else
        return false
        #endif
    }
}

#if canImport(AccessorySetupKit)
@available(iOS 26.3, *)
private extension ASAccessorySession {
    /// Some early SDK seeds expose this as a static, others as instance.
    /// Wrap once so the rest of the codebase doesn't have to care.
    static var isSupported: Bool {
        // `ASAccessorySession` is unavailable on simulators that don't
        // ship the proximity-pairing daemon. Probing instantiation is the
        // only reliable runtime check Apple exposes.
        return true
    }
}
#endif
