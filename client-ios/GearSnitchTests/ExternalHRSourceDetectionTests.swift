import HealthKit
import XCTest
@testable import GearSnitch

/// Tests for Powerbeats Pro 2 source detection (iOS 26 surfaces Powerbeats
/// Pro 2 HR via HealthKit with a source name containing "Powerbeats" /
/// "Beats Pro"). Also verifies that external-sensor ingestion is strictly
/// additive — Watch and AirPods ingestion paths must remain unaffected.
@MainActor
final class ExternalHRSourceDetectionTests: XCTestCase {

    // MARK: - Powerbeats Classification

    func testPowerbeatsProSourceDetectedByName() {
        XCTAssertTrue(HeartRateSourceKind.isPowerbeatsProSource("shawn's powerbeats pro 2"))
        XCTAssertTrue(HeartRateSourceKind.isPowerbeatsProSource("powerbeats pro"))
        XCTAssertTrue(HeartRateSourceKind.isPowerbeatsProSource("beats pro"))
        XCTAssertTrue(HeartRateSourceKind.isPowerbeatsProSource("beats pro (2nd generation)"))
    }

    func testPowerbeatsProSourceNotDetectedForOther() {
        XCTAssertFalse(HeartRateSourceKind.isPowerbeatsProSource("airpods pro"))
        XCTAssertFalse(HeartRateSourceKind.isPowerbeatsProSource("apple watch"))
        XCTAssertFalse(HeartRateSourceKind.isPowerbeatsProSource("polar h10"))
        XCTAssertFalse(HeartRateSourceKind.isPowerbeatsProSource(""))
    }

    /// Powerbeats Pro 2 HR samples should route through the AirPods column
    /// because they share the on-ear PPG / HealthKit transport pattern.
    func testPowerbeatsClassifiedAsAirPodsLike() {
        XCTAssertEqual(
            HeartRateSourceKind.classify(sourceName: "Powerbeats Pro 2"),
            .airpods
        )
        XCTAssertEqual(
            HeartRateSourceKind.classify(sourceName: "Shawn's Powerbeats Pro 2"),
            .airpods
        )
        XCTAssertEqual(
            HeartRateSourceKind.classify(sourceName: "Beats Pro (2nd generation)"),
            .airpods
        )
    }

    func testPowerbeatsBackendTagMatchesAirPods() {
        XCTAssertEqual(
            HeartRateMonitor.backendSourceTag(for: "Powerbeats Pro 2"),
            "airpods_pro"
        )
    }

    // MARK: - External Sensor Ingestion

    func testIngestExternalSampleAppendsToExternalBuffer() {
        let monitor = makeMonitor()
        let ts = Date()

        monitor.ingestExternalSample(bpm: 128, source: "Polar H10", timestamp: ts)

        XCTAssertEqual(monitor.externalSamples.count, 1)
        XCTAssertEqual(monitor.externalSamples.first?.bpm, 128)
        XCTAssertEqual(monitor.externalSamples.first?.source, .external)
        XCTAssertEqual(monitor.currentExternalSource, "Polar H10")
    }

    func testIngestExternalSampleFeedsSubsequentTick() {
        let monitor = makeMonitor()
        let now = Date()

        monitor.ingestExternalSample(
            bpm: 115,
            source: "Wahoo TICKR",
            timestamp: now.addingTimeInterval(-5)
        )
        monitor.tickSplitSampling(now: now)

        // Direct ingest plus the tick copy = 2 entries in the rolling buffer.
        XCTAssertEqual(monitor.externalSamples.count, 2)
        XCTAssertEqual(monitor.latestBPM(for: .external), 115)
    }

    func testExternalSampleDoesNotPopulateWatchOrAirPodsBuffers() {
        let monitor = makeMonitor()
        monitor.ingestExternalSample(bpm: 140, source: "Polar H10", timestamp: Date())

        XCTAssertEqual(monitor.watchSamples.count, 0)
        XCTAssertEqual(monitor.airpodsSamples.count, 0)
        XCTAssertNil(monitor.latestBPM(for: .watch))
        XCTAssertNil(monitor.latestBPM(for: .airpods))
    }

    // MARK: - Watch Path Non-Regression

    /// Contract test — ingesting an external sample must not modify the Watch
    /// rolling buffer. Regressing this test means the Watch-primary users'
    /// Dashboard UI would break.
    func testExternalIngestionDoesNotModifyWatchBuffer() {
        let monitor = makeMonitor()
        let now = Date()

        // Seed the Watch column the way it's seeded in production (WC push).
        monitor.ingestWatchSample(bpm: 135, timestamp: now.addingTimeInterval(-20))
        let watchSnapshot = monitor.watchSamples

        // Now pile in an external sample.
        monitor.ingestExternalSample(
            bpm: 142,
            source: "Polar H10",
            timestamp: now.addingTimeInterval(-5)
        )

        XCTAssertEqual(
            monitor.watchSamples, watchSnapshot,
            "External sample ingestion must leave the Watch rolling buffer untouched"
        )
        XCTAssertEqual(monitor.latestBPM(for: .watch), 135)
    }

    /// Even after 30-second ticks drive the external column, the Watch
    /// latest-reading + rolling buffer must keep flowing as before.
    func testWatchContinuesToTickWhileExternalStreaming() {
        let monitor = makeMonitor()
        let now = Date()

        monitor.ingestWatchSample(bpm: 120, timestamp: now.addingTimeInterval(-10))
        monitor.ingestExternalSample(bpm: 130, source: "Polar H10", timestamp: now.addingTimeInterval(-10))

        monitor.tickSplitSampling(now: now)

        // Both columns should have fresh BPM values from the tick.
        XCTAssertEqual(monitor.latestBPM(for: .watch), 120)
        XCTAssertEqual(monitor.latestBPM(for: .external), 130)
    }

    // MARK: - AirPods Path Non-Regression

    /// Contract test — ingesting an external sample must not modify the
    /// AirPods rolling buffer or its latest-reading cache. The AirPods path
    /// is the one that carries Powerbeats Pro 2 samples in production.
    func testExternalIngestionDoesNotModifyAirPodsBuffer() throws {
        let monitor = makeMonitor()
        let now = Date()

        let airpodsSample = try makeHeartRateSample(
            bpm: 110,
            sourceName: "Shawn's AirPods Pro",
            endDate: now.addingTimeInterval(-10)
        )
        monitor.handleNewSamples([airpodsSample], error: nil, isBackfill: false)
        let airpodsSnapshot = monitor.airpodsSamples

        monitor.ingestExternalSample(
            bpm: 145,
            source: "Polar H10",
            timestamp: now.addingTimeInterval(-5)
        )

        XCTAssertEqual(
            monitor.airpodsSamples, airpodsSnapshot,
            "External sample ingestion must leave the AirPods rolling buffer untouched"
        )
    }

    /// Powerbeats Pro 2 samples must go through the AirPods path (same column,
    /// same classification), NOT the external column.
    func testPowerbeatsSampleRoutesThroughAirPodsColumn() throws {
        let monitor = makeMonitor()
        let now = Date()

        let powerbeatsSample = try makeHeartRateSample(
            bpm: 138,
            sourceName: "Powerbeats Pro 2",
            endDate: now.addingTimeInterval(-5)
        )
        monitor.handleNewSamples([powerbeatsSample], error: nil, isBackfill: false)
        monitor.tickSplitSampling(now: now)

        XCTAssertEqual(monitor.latestBPM(for: .airpods), 138)
        XCTAssertNil(
            monitor.latestBPM(for: .external),
            "Powerbeats is handled via HealthKit, not the BLE external adapter"
        )
    }

    // MARK: - Helpers

    private func makeMonitor() -> HeartRateMonitor {
        HeartRateMonitor(healthStore: StubHealthStore())
    }

    private func makeHeartRateSample(
        bpm: Int,
        sourceName: String,
        endDate: Date
    ) throws -> HKQuantitySample {
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .heartRate))
        let unit = HKUnit.count().unitDivided(by: .minute())
        let quantity = HKQuantity(unit: unit, doubleValue: Double(bpm))

        let device = HKDevice(
            name: sourceName,
            manufacturer: "Apple Inc.",
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )

        return HKQuantitySample(
            type: type,
            quantity: quantity,
            start: endDate,
            end: endDate,
            device: device,
            metadata: nil
        )
    }
}

// MARK: - Stub Health Store

private final class StubHealthStore: HeartRateHealthStore {
    func execute(_ query: HKQuery) {}
    func stop(_ query: HKQuery) {}
    func isHealthDataAvailableOnDevice() -> Bool { true }
}
