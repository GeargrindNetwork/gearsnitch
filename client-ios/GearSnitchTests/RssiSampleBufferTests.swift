import XCTest
@testable import GearSnitch

/// Unit tests for `RssiSampleBuffer` (backlog item #19). Covers the
/// flush rules (5-minute age OR 20-sample count, whichever first), the
/// invalid-sentinel drop, and the per-device fan-out so batches from
/// different paired devices don't collide.
@MainActor
final class RssiSampleBufferTests: XCTestCase {

    // MARK: - Flush on batch-size

    func testFlushesWhenMaxBatchSizeReached() async {
        let buffer = RssiSampleBuffer()
        var flushes: [(String, [RssiSample])] = []
        buffer.postSamples = { id, samples in flushes.append((id, samples)) }

        let start = Date()
        // 19 samples — below the 20-sample threshold.
        for i in 0..<19 {
            buffer.record(
                rssi: -60 - i,
                persistedDeviceId: "dev-a",
                now: start.addingTimeInterval(TimeInterval(i))
            )
        }
        await Task.yield()
        XCTAssertTrue(flushes.isEmpty, "No flush before batch size hit")
        XCTAssertEqual(buffer.bufferedCount(forDevice: "dev-a"), 19)

        // 20th sample triggers the flush.
        buffer.record(
            rssi: -80,
            persistedDeviceId: "dev-a",
            now: start.addingTimeInterval(20)
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(flushes.count, 1, "Flushes once the 20-sample batch fills")
        XCTAssertEqual(flushes.first?.0, "dev-a")
        XCTAssertEqual(flushes.first?.1.count, 20)
        XCTAssertEqual(buffer.bufferedCount(forDevice: "dev-a"), 0, "Buffer cleared after flush")
    }

    // MARK: - Flush on time-based trigger

    func testFlushesAfterFiveMinutesEvenWithFewerSamples() async {
        let buffer = RssiSampleBuffer()
        var flushes: [(String, [RssiSample])] = []
        buffer.postSamples = { id, samples in flushes.append((id, samples)) }

        let start = Date()
        // First sample kicks off the clock.
        buffer.record(rssi: -55, persistedDeviceId: "dev-b", now: start)
        await Task.yield()
        XCTAssertTrue(flushes.isEmpty, "No flush on the very first sample")

        // 4 minutes later — still within flushInterval.
        buffer.record(
            rssi: -58,
            persistedDeviceId: "dev-b",
            now: start.addingTimeInterval(4 * 60)
        )
        await Task.yield()
        XCTAssertTrue(flushes.isEmpty, "No flush within 5-min window")

        // 5 minutes after the *oldest* sample — flush fires.
        buffer.record(
            rssi: -62,
            persistedDeviceId: "dev-b",
            now: start.addingTimeInterval(5 * 60 + 1)
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(flushes.count, 1, "Flushes once the oldest sample crosses 5min")
        XCTAssertEqual(flushes.first?.1.count, 3, "All 3 samples included in the flush")
    }

    // MARK: - shouldFlush pure predicate

    func testShouldFlushHonoursBothTriggers() {
        let buffer = RssiSampleBuffer(
            maxBatchSize: 20,
            flushInterval: 5 * 60
        )

        // Under both thresholds → no flush.
        let under: [RssiSample] = (0..<5).map {
            RssiSample(rssi: -60, sampledAt: Date().addingTimeInterval(TimeInterval($0)))
        }
        XCTAssertFalse(buffer.shouldFlush(buffer: under, now: Date().addingTimeInterval(10)))

        // At count threshold → flush.
        let atCount: [RssiSample] = (0..<20).map {
            RssiSample(rssi: -60, sampledAt: Date().addingTimeInterval(TimeInterval($0)))
        }
        XCTAssertTrue(buffer.shouldFlush(buffer: atCount, now: Date().addingTimeInterval(100)))

        // At time threshold → flush.
        let oldest = Date()
        let aged: [RssiSample] = [
            RssiSample(rssi: -60, sampledAt: oldest),
            RssiSample(rssi: -60, sampledAt: oldest.addingTimeInterval(60)),
        ]
        XCTAssertTrue(
            buffer.shouldFlush(buffer: aged, now: oldest.addingTimeInterval(5 * 60 + 1))
        )
    }

    // MARK: - Invalid RSSI sentinel is dropped

    func testInvalidSentinelIsDropped() async {
        let buffer = RssiSampleBuffer()
        var flushCount = 0
        buffer.postSamples = { _, _ in flushCount += 1 }

        buffer.record(rssi: 127, persistedDeviceId: "dev-c")

        await Task.yield()
        XCTAssertEqual(buffer.bufferedCount(forDevice: "dev-c"), 0)
        XCTAssertEqual(flushCount, 0)
    }

    // MARK: - Unpaired peripherals are silently dropped

    func testUnpairedPeripheralsAreDropped() async {
        let buffer = RssiSampleBuffer()
        var flushCount = 0
        buffer.postSamples = { _, _ in flushCount += 1 }

        buffer.record(rssi: -60, persistedDeviceId: nil)

        await Task.yield()
        XCTAssertEqual(flushCount, 0, "No flush when no persisted id is known")
    }

    // MARK: - Per-device buffers are independent

    func testBuffersAreScopedPerDevice() async {
        let buffer = RssiSampleBuffer()
        var perDeviceFlushes: [String: Int] = [:]
        buffer.postSamples = { id, samples in
            perDeviceFlushes[id, default: 0] += samples.count
        }

        // Fill dev-x to 20 but dev-y to only 5.
        let start = Date()
        for i in 0..<20 {
            buffer.record(
                rssi: -60,
                persistedDeviceId: "dev-x",
                now: start.addingTimeInterval(TimeInterval(i))
            )
        }
        for i in 0..<5 {
            buffer.record(
                rssi: -70,
                persistedDeviceId: "dev-y",
                now: start.addingTimeInterval(TimeInterval(i))
            )
        }
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(perDeviceFlushes["dev-x"], 20, "dev-x flushed on batch-size")
        XCTAssertNil(perDeviceFlushes["dev-y"], "dev-y below both thresholds, not flushed")
        XCTAssertEqual(buffer.bufferedCount(forDevice: "dev-y"), 5)
    }

    // MARK: - flushAll pushes every buffered device

    func testFlushAllDrainsEveryDevice() async {
        let buffer = RssiSampleBuffer()
        var perDeviceFlushes: [String: Int] = [:]
        buffer.postSamples = { id, samples in
            perDeviceFlushes[id, default: 0] += samples.count
        }

        buffer.record(rssi: -60, persistedDeviceId: "dev-1")
        buffer.record(rssi: -65, persistedDeviceId: "dev-2")
        buffer.record(rssi: -70, persistedDeviceId: "dev-2")

        buffer.flushAll()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(perDeviceFlushes["dev-1"], 1)
        XCTAssertEqual(perDeviceFlushes["dev-2"], 2)
        XCTAssertEqual(buffer.bufferedCount(forDevice: "dev-1"), 0)
        XCTAssertEqual(buffer.bufferedCount(forDevice: "dev-2"), 0)
    }

    // MARK: - Out-of-range values are clamped

    func testRecordClampsRssiIntoServerAcceptedRange() async {
        let buffer = RssiSampleBuffer()
        var captured: [RssiSample] = []
        buffer.postSamples = { _, samples in captured.append(contentsOf: samples) }

        buffer.record(rssi: 10, persistedDeviceId: "dev-z") // > 0
        buffer.record(rssi: -200, persistedDeviceId: "dev-z") // < -120

        buffer.flushAll()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].rssi, 0, "Values above 0 clamp to 0")
        XCTAssertEqual(captured[1].rssi, -120, "Values below -120 clamp to -120")
    }
}
