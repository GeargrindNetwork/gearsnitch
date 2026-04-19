import HealthKit
import XCTest
@testable import GearSnitch

/// Tests for heart rate source attribution — the mechanism that lets the
/// Dashboard HR card show a "via AirPods Pro" subtitle when AirPods Pro 3
/// emit heart rate samples through HealthKit. AirPods Pro 3 do not expose
/// heart rate over a BLE GATT service; Apple writes HR into HealthKit with
/// a source revision whose `source.name` contains "AirPods", and the
/// sample's `device.name` may also carry the AirPods name.
final class HeartRateMonitorTests: XCTestCase {

    // MARK: - HeartRateSourceKind Classification

    func testClassifyAirPodsByName() {
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: "Shawn's AirPods Pro"), .airpods)
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: "AirPods"), .airpods)
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: "airpods pro 3"), .airpods)
    }

    func testClassifyWatchByName() {
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: "Shawn's Apple Watch"), .watch)
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: "Apple Watch Ultra 2"), .watch)
    }

    func testClassifyPhoneByName() {
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: "iPhone 17 Pro"), .phone)
    }

    func testClassifyOtherByName() {
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: "Polar H10"), .other)
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: "MyFitnessPal"), .other)
    }

    func testClassifyUnknownForNilOrEmpty() {
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: nil), .unknown)
        XCTAssertEqual(HeartRateSourceKind.classify(sourceName: ""), .unknown)
    }

    // MARK: - Backend Source Tag

    func testBackendSourceTagAirPods() {
        XCTAssertEqual(HeartRateMonitor.backendSourceTag(for: "Shawn's AirPods Pro"), "airpods_pro")
    }

    func testBackendSourceTagAppleWatch() {
        XCTAssertEqual(HeartRateMonitor.backendSourceTag(for: "Apple Watch Series 10"), "apple_watch")
    }

    func testBackendSourceTagIPhone() {
        XCTAssertEqual(HeartRateMonitor.backendSourceTag(for: "iPhone 17"), "iphone")
    }

    func testBackendSourceTagOther() {
        XCTAssertEqual(HeartRateMonitor.backendSourceTag(for: "Polar H10"), "healthkit")
    }

    func testBackendSourceTagUnknown() {
        XCTAssertEqual(HeartRateMonitor.backendSourceTag(for: nil), "unknown")
    }

    // MARK: - Device Name Extraction (HKDevice path)

    /// When HealthKit provides an `HKDevice` on the sample, the monitor
    /// should prefer `device.name` over the sourceRevision. This is the path
    /// AirPods Pro 3 samples typically take when Apple attaches the AirPods
    /// `HKDevice` to the written quantity sample.
    @MainActor
    func testExtractSourceDeviceNameFromHKDevice() throws {
        let monitor = HeartRateMonitor(healthStore: StubHealthStore())

        let device = HKDevice(
            name: "Shawn's AirPods Pro",
            manufacturer: "Apple Inc.",
            model: "AirPods Pro (3rd generation)",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )

        let sample = try makeHeartRateSample(bpm: 128, device: device)
        let name = monitor.extractSourceDeviceName(from: sample)

        XCTAssertEqual(name, "Shawn's AirPods Pro")
    }

    @MainActor
    func testExtractSourceDeviceNameFallsBackToModel() throws {
        let monitor = HeartRateMonitor(healthStore: StubHealthStore())

        let device = HKDevice(
            name: nil,
            manufacturer: "Apple Inc.",
            model: "AirPods Pro (3rd generation)",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )

        let sample = try makeHeartRateSample(bpm: 120, device: device)
        XCTAssertEqual(
            monitor.extractSourceDeviceName(from: sample),
            "AirPods Pro (3rd generation)"
        )
    }

    // MARK: - Observer → UI Binding

    /// When a new HR sample arrives via the observer query, the monitor's
    /// published state should update so the Dashboard card re-renders.
    @MainActor
    func testObserverUpdatesPublishedHeartRate() throws {
        let monitor = HeartRateMonitor(healthStore: StubHealthStore())

        XCTAssertNil(monitor.currentBPM)

        let sample = try makeHeartRateSample(bpm: 144, device: nil)
        monitor.handleNewSamples([sample], error: nil, isBackfill: false)

        XCTAssertEqual(monitor.currentBPM, 144)
        XCTAssertEqual(monitor.currentZone, .cardio)
    }

    /// Backfill path should publish the single most recent sample (not
    /// every historical sample) so we don't retro-upload duplicates.
    @MainActor
    func testBackfillPublishesLatestSampleOnly() throws {
        let monitor = HeartRateMonitor(healthStore: StubHealthStore())

        let now = Date()
        let older = try makeHeartRateSample(
            bpm: 88,
            device: nil,
            start: now.addingTimeInterval(-300),
            end: now.addingTimeInterval(-300)
        )
        let newer = try makeHeartRateSample(
            bpm: 132,
            device: nil,
            start: now.addingTimeInterval(-5),
            end: now.addingTimeInterval(-5)
        )

        monitor.handleNewSamples([older, newer], error: nil, isBackfill: true)

        // Only the newer sample should be reflected in published state.
        XCTAssertEqual(monitor.currentBPM, 132)
        XCTAssertEqual(monitor.currentZone, .fatBurn)
    }

    /// An observer error should not clobber published state or crash.
    @MainActor
    func testObserverErrorDoesNotMutateState() {
        let monitor = HeartRateMonitor(healthStore: StubHealthStore())
        monitor.handleNewSamples(nil, error: NSError(domain: "HK", code: 1), isBackfill: false)
        XCTAssertNil(monitor.currentBPM)
    }

    // MARK: - Helpers

    private func makeHeartRateSample(
        bpm: Int,
        device: HKDevice?,
        start: Date = Date(),
        end: Date = Date()
    ) throws -> HKQuantitySample {
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .heartRate))
        let unit = HKUnit.count().unitDivided(by: .minute())
        let quantity = HKQuantity(unit: unit, doubleValue: Double(bpm))
        return HKQuantitySample(
            type: type,
            quantity: quantity,
            start: start,
            end: end,
            device: device,
            metadata: nil
        )
    }
}

// MARK: - Stub Health Store

/// Test double for HKHealthStore — the monitor's init takes a protocol, so
/// tests can verify behavior without touching the real HealthKit authorization
/// state of the simulator/device.
private final class StubHealthStore: HeartRateHealthStore {
    var executedQueries: [HKQuery] = []
    var stoppedQueries: [HKQuery] = []
    var healthDataAvailable: Bool = true

    func execute(_ query: HKQuery) {
        executedQueries.append(query)
    }

    func stop(_ query: HKQuery) {
        stoppedQueries.append(query)
    }

    func isHealthDataAvailableOnDevice() -> Bool {
        healthDataAvailable
    }
}
