import HealthKit
import XCTest
@testable import GearSnitch

/// Tests for the split-column Watch / AirPods heart-rate buffers that drive
/// the Dashboard correlation UI. These exercise:
///
/// 1. The 30-second `tickSplitSampling` loop behavior (fresh reading vs.
///    gap placeholder)
/// 2. The 5-minute rolling-window eviction policy on every append
/// 3. The WatchConnectivity fast-path (`ingestWatchSample`) that bypasses
///    HealthKit auto-sync latency
/// 4. The Δ correlation badge math used under the columns
/// 5. Empty-buffer UI state (latest BPM + Δ both report `nil` → "—")
@MainActor
final class HeartRateMonitorSplitTests: XCTestCase {

    // MARK: - 30-Second Tick → Buffer Append

    func testTickAppendsGapWhenNoReadingsCached() throws {
        let monitor = makeMonitor()

        XCTAssertEqual(monitor.watchSamples.count, 0)
        XCTAssertEqual(monitor.airpodsSamples.count, 0)

        monitor.tickSplitSampling(now: Date())

        // With no HealthKit samples fed in, both buffers get one gap entry.
        XCTAssertEqual(monitor.watchSamples.count, 1)
        XCTAssertEqual(monitor.airpodsSamples.count, 1)
        XCTAssertNil(monitor.watchSamples.first?.bpm)
        XCTAssertNil(monitor.airpodsSamples.first?.bpm)
        XCTAssertEqual(monitor.watchSamples.first?.source, .watch)
        XCTAssertEqual(monitor.airpodsSamples.first?.source, .airpods)
    }

    func testTickAppendsBPMWhenRecentHealthKitSampleAvailable() throws {
        let monitor = makeMonitor()
        let now = Date()

        // Seed the monitor with a fresh HealthKit sample from the Watch.
        let watchSample = try makeHeartRateSample(
            bpm: 142,
            sourceName: "Shawn's Apple Watch",
            endDate: now.addingTimeInterval(-10)
        )
        monitor.handleNewSamples([watchSample], error: nil, isBackfill: false)

        monitor.tickSplitSampling(now: now)

        XCTAssertEqual(monitor.watchSamples.count, 1)
        XCTAssertEqual(monitor.watchSamples.first?.bpm, 142)
        // AirPods had nothing cached → gap.
        XCTAssertEqual(monitor.airpodsSamples.count, 1)
        XCTAssertNil(monitor.airpodsSamples.first?.bpm)
    }

    func testTickAppendsGapWhenCachedReadingIsStale() throws {
        let monitor = makeMonitor()
        let now = Date()

        // Seed a reading older than the 60-second freshness window.
        let oldSample = try makeHeartRateSample(
            bpm: 115,
            sourceName: "Apple Watch Ultra",
            endDate: now.addingTimeInterval(-120)
        )
        monitor.handleNewSamples([oldSample], error: nil, isBackfill: false)

        monitor.tickSplitSampling(now: now)

        XCTAssertEqual(monitor.watchSamples.count, 1)
        XCTAssertNil(
            monitor.watchSamples.first?.bpm,
            "Watch reading older than the freshness window must land as a gap"
        )
    }

    func testTickSeparatesWatchAndAirPodsReadings() throws {
        let monitor = makeMonitor()
        let now = Date()

        let watchSample = try makeHeartRateSample(
            bpm: 150,
            sourceName: "Apple Watch Series 10",
            endDate: now.addingTimeInterval(-5)
        )
        let airpodsSample = try makeHeartRateSample(
            bpm: 132,
            sourceName: "Shawn's AirPods Pro",
            endDate: now.addingTimeInterval(-5)
        )
        monitor.handleNewSamples(
            [watchSample, airpodsSample],
            error: nil,
            isBackfill: false
        )

        monitor.tickSplitSampling(now: now)

        XCTAssertEqual(monitor.watchSamples.first?.bpm, 150)
        XCTAssertEqual(monitor.airpodsSamples.first?.bpm, 132)
    }

    // MARK: - 5-Minute Rolling Window Eviction

    func testBufferEvictsSamplesOlderThanFiveMinutes() throws {
        let monitor = makeMonitor()
        let now = Date()

        // Push an ancient Watch tick from 6 minutes ago. The cache's
        // "latest reading" check will treat it as stale (gap), and the
        // append happens at `now - 6min`, which on the NEXT tick at `now`
        // should evict.
        monitor.tickSplitSampling(now: now.addingTimeInterval(-6 * 60))
        XCTAssertEqual(monitor.watchSamples.count, 1)

        // Tick at "now" — the 6-minute-old gap should be evicted because
        // it is now outside the 5-minute window relative to `now`.
        monitor.tickSplitSampling(now: now)

        XCTAssertEqual(
            monitor.watchSamples.count,
            1,
            "Only the fresh tick should remain; the 6-minute-old entry must be evicted"
        )
        XCTAssertEqual(monitor.watchSamples.first?.timestamp, now)
    }

    func testBufferKeepsAllSamplesWithinFiveMinutes() throws {
        let monitor = makeMonitor()
        let now = Date()

        // Four ticks spaced 60 seconds apart, all within the 5-minute window.
        for offset in stride(from: 240.0, through: 0.0, by: -60.0) {
            monitor.tickSplitSampling(now: now.addingTimeInterval(-offset))
        }

        XCTAssertEqual(monitor.watchSamples.count, 5)
        XCTAssertEqual(monitor.airpodsSamples.count, 5)
    }

    // MARK: - WatchConnectivity Fast-Path

    func testIngestWatchSampleAppendsToWatchBuffer() {
        let monitor = makeMonitor()
        let ts = Date()

        monitor.ingestWatchSample(bpm: 137, timestamp: ts)

        XCTAssertEqual(monitor.watchSamples.count, 1)
        XCTAssertEqual(monitor.watchSamples.first?.bpm, 137)
        XCTAssertEqual(monitor.watchSamples.first?.source, .watch)
        // Does NOT cross-contaminate the AirPods buffer.
        XCTAssertEqual(monitor.airpodsSamples.count, 0)
    }

    func testIngestWatchSampleFeedsSubsequentTick() {
        let monitor = makeMonitor()
        let now = Date()

        // WC arrives 10 seconds before the 30-second tick.
        monitor.ingestWatchSample(bpm: 121, timestamp: now.addingTimeInterval(-10))
        monitor.tickSplitSampling(now: now)

        // The WC push is in the buffer directly AND the subsequent tick sees
        // the cached reading as fresh, so it appends a second entry with the
        // same BPM.
        XCTAssertEqual(monitor.watchSamples.count, 2)
        XCTAssertEqual(monitor.watchSamples.last?.bpm, 121)
    }

    func testIngestWatchSampleEvictsOldEntries() {
        let monitor = makeMonitor()
        let now = Date()

        // Seed an old WC sample that is now outside the 5-minute window.
        monitor.ingestWatchSample(
            bpm: 90,
            timestamp: now.addingTimeInterval(-6 * 60)
        )
        // A fresh ingest must evict the old one.
        monitor.ingestWatchSample(bpm: 145, timestamp: now)

        XCTAssertEqual(monitor.watchSamples.count, 1)
        XCTAssertEqual(monitor.watchSamples.first?.bpm, 145)
    }

    // MARK: - Δ Correlation

    func testDeltaReportsAbsoluteDifference() {
        let monitor = makeMonitor()
        let now = Date()

        monitor.ingestWatchSample(bpm: 140, timestamp: now)
        // Drive an AirPods sample through the HealthKit path.
        let airpodsSample = try? makeHeartRateSample(
            bpm: 133,
            sourceName: "AirPods Pro",
            endDate: now
        )
        if let s = airpodsSample {
            monitor.handleNewSamples([s], error: nil, isBackfill: false)
            monitor.tickSplitSampling(now: now)
        }

        XCTAssertEqual(monitor.latestHeartRateDelta, 7)
    }

    func testDeltaIsSymmetric() {
        let monitor = makeMonitor()
        let now = Date()

        monitor.ingestWatchSample(bpm: 110, timestamp: now)
        let airpodsSample = try? makeHeartRateSample(
            bpm: 150,
            sourceName: "AirPods Pro",
            endDate: now
        )
        if let s = airpodsSample {
            monitor.handleNewSamples([s], error: nil, isBackfill: false)
            monitor.tickSplitSampling(now: now)
        }

        // Watch=110, AirPods=150 → Δ = 40 (absolute, not signed)
        XCTAssertEqual(monitor.latestHeartRateDelta, 40)
    }

    func testDeltaIsNilWhenEitherBufferIsEmpty() {
        let monitor = makeMonitor()

        XCTAssertNil(monitor.latestHeartRateDelta)

        monitor.ingestWatchSample(bpm: 120, timestamp: Date())
        XCTAssertNil(
            monitor.latestHeartRateDelta,
            "Watch-only readings should leave Δ undefined"
        )
    }

    func testDeltaIgnoresGapPlaceholders() {
        let monitor = makeMonitor()
        let now = Date()

        // Two gap ticks — neither column has a real reading.
        monitor.tickSplitSampling(now: now.addingTimeInterval(-60))
        monitor.tickSplitSampling(now: now)

        XCTAssertNil(monitor.latestHeartRateDelta)
    }

    // MARK: - Empty Buffer → "—" State

    func testLatestBPMIsNilForEmptyBuffers() {
        let monitor = makeMonitor()

        XCTAssertNil(monitor.latestBPM(for: .watch))
        XCTAssertNil(monitor.latestBPM(for: .airpods))
    }

    func testLatestBPMIgnoresGapOnlyBuffers() {
        let monitor = makeMonitor()
        let now = Date()

        // Fill both buffers with gap-only entries.
        monitor.tickSplitSampling(now: now.addingTimeInterval(-120))
        monitor.tickSplitSampling(now: now.addingTimeInterval(-60))
        monitor.tickSplitSampling(now: now)

        XCTAssertNil(monitor.latestBPM(for: .watch))
        XCTAssertNil(monitor.latestBPM(for: .airpods))
        XCTAssertNil(monitor.latestHeartRateDelta)
    }

    func testLatestBPMReturnsMostRecentNonNilReading() {
        let monitor = makeMonitor()
        let now = Date()

        monitor.ingestWatchSample(bpm: 100, timestamp: now.addingTimeInterval(-60))
        monitor.ingestWatchSample(bpm: 135, timestamp: now)

        XCTAssertEqual(monitor.latestBPM(for: .watch), 135)
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

        // Name-in-device route — matches the AirPods path Apple uses.
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

/// Minimal `HeartRateHealthStore` double — the split tests never exercise
/// the actual anchored query, so `execute`/`stop` are recorded for visibility
/// but otherwise inert.
private final class StubHealthStore: HeartRateHealthStore {
    var executedQueries: [HKQuery] = []
    var stoppedQueries: [HKQuery] = []

    func execute(_ query: HKQuery) {
        executedQueries.append(query)
    }

    func stop(_ query: HKQuery) {
        stoppedQueries.append(query)
    }

    func isHealthDataAvailableOnDevice() -> Bool { true }
}
