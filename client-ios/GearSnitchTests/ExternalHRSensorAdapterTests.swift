import XCTest
@testable import GearSnitch

/// Byte-level unit tests for the BLE Heart Rate Measurement decoder used by
/// `ExternalHRSensorAdapter`. Fixtures come from the Bluetooth SIG Heart Rate
/// Profile spec:
///
/// Flags (1 byte)
///   bit 0: HR value format (0 = UInt8, 1 = UInt16)
///   bit 1: Sensor Contact Status bit 1
///   bit 2: Sensor Contact Support
///   bit 3: Energy Expended present (UInt16, kJ)
///   bit 4: RR-Interval present (UInt16[], resolution 1/1024s)
final class ExternalHRSensorAdapterTests: XCTestCase {

    // MARK: - UInt8 / UInt16 BPM

    func testDecodesUInt8BPM() {
        // flags=0x00 (UInt8 BPM, nothing else), bpm=72
        let data = Data([0x00, 72])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.bpm, 72)
        XCTAssertNil(decoded?.energyExpendedKJ)
        XCTAssertEqual(decoded?.rrIntervals, [])
    }

    func testDecodesUInt16BPM() {
        // flags=0x01 (UInt16 BPM), bpm=300 → 0x012C little-endian
        let data = Data([0x01, 0x2C, 0x01])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.bpm, 300)
    }

    // MARK: - Sensor Contact Bits

    func testSensorContactSupportedButNotDetected() {
        // flags=0x04 (contact supported) + bit1 clear (not detected), bpm=60
        let data = Data([0x04, 60])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.sensorContactSupported, true)
        XCTAssertEqual(decoded?.sensorContactDetected, false)
    }

    func testSensorContactSupportedAndDetected() {
        // flags=0x06 (contact supported + detected), bpm=80
        let data = Data([0x06, 80])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.sensorContactSupported, true)
        XCTAssertEqual(decoded?.sensorContactDetected, true)
    }

    func testSensorContactUnsupportedAssumesDetected() {
        // flags=0x00 → contact feature not supported; detection reported true
        // so higher-level code can treat as valid.
        let data = Data([0x00, 75])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.sensorContactSupported, false)
        XCTAssertEqual(decoded?.sensorContactDetected, true)
    }

    // MARK: - Energy Expended

    func testDecodesEnergyExpended() {
        // flags=0x08 (energy present), bpm=100, energy=1024 (0x0400 LE)
        let data = Data([0x08, 100, 0x00, 0x04])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.bpm, 100)
        XCTAssertEqual(decoded?.energyExpendedKJ, 1024)
    }

    // MARK: - RR Intervals

    func testDecodesRRIntervals() {
        // flags=0x10 (RR present), bpm=120, one RR=1024 (→ 1.0 s).
        let data = Data([0x10, 120, 0x00, 0x04])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.bpm, 120)
        XCTAssertEqual(decoded?.rrIntervals.count, 1)
        XCTAssertEqual(decoded?.rrIntervals.first ?? 0, 1.0, accuracy: 0.001)
    }

    func testDecodesMultipleRRIntervals() {
        // flags=0x10, bpm=140, RR=[512 (0.5s), 768 (0.75s)]
        let data = Data([0x10, 140, 0x00, 0x02, 0x00, 0x03])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.rrIntervals.count, 2)
        XCTAssertEqual(decoded?.rrIntervals[0] ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded?.rrIntervals[1] ?? 0, 0.75, accuracy: 0.001)
    }

    func testDecodesEnergyAndRRTogether() {
        // flags=0x18 (energy + RR), bpm=110, energy=500 (0x01F4),
        // RR=[256 (0.25s)]
        let data = Data([0x18, 110, 0xF4, 0x01, 0x00, 0x01])
        let decoded = HeartRateMeasurement.decode(data)
        XCTAssertEqual(decoded?.bpm, 110)
        XCTAssertEqual(decoded?.energyExpendedKJ, 500)
        XCTAssertEqual(decoded?.rrIntervals.count, 1)
        XCTAssertEqual(decoded?.rrIntervals.first ?? 0, 0.25, accuracy: 0.001)
    }

    // MARK: - Truncated / Malformed

    func testDecodeReturnsNilOnEmptyData() {
        XCTAssertNil(HeartRateMeasurement.decode(Data()))
    }

    func testDecodeReturnsNilOnOneByte() {
        XCTAssertNil(HeartRateMeasurement.decode(Data([0x00])))
    }

    func testDecodeReturnsNilOnTruncatedUInt16() {
        // flags declares UInt16 BPM but only one BPM byte follows.
        XCTAssertNil(HeartRateMeasurement.decode(Data([0x01, 0x2C])))
    }

    func testDecodeReturnsNilOnMissingEnergy() {
        // flags=0x08 says energy present, but we only supplied 1 energy byte.
        XCTAssertNil(HeartRateMeasurement.decode(Data([0x08, 100, 0x00])))
    }

    // MARK: - Forwarding to Monitor

    /// Confirms that a decoded BLE HR Profile measurement routes through to
    /// `HeartRateMonitor.ingestExternalSample(...)` via the adapter's
    /// sink — the same path the Settings toggle enables.
    @MainActor
    func testHandleDecodedMeasurementForwardsToSink() {
        let sink = RecordingSink()
        let adapter = ExternalHRSensorAdapter()
        adapter.configure(sink: sink)

        let measurement = HeartRateMeasurement(
            bpm: 142,
            energyExpendedKJ: nil,
            rrIntervals: [],
            sensorContactSupported: true,
            sensorContactDetected: true
        )
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        adapter.handleDecodedMeasurement(
            measurement,
            sensorID: UUID(),
            sourceName: "Polar H10",
            timestamp: ts
        )

        XCTAssertEqual(sink.captured.count, 1)
        XCTAssertEqual(sink.captured.first?.bpm, 142)
        XCTAssertEqual(sink.captured.first?.source, "Polar H10")
        XCTAssertEqual(sink.captured.first?.timestamp, ts)
    }

    @MainActor
    func testAdapterEnabledToggleUpdatesState() {
        let adapter = ExternalHRSensorAdapter()
        let id = UUID()
        XCTAssertFalse(adapter.isEnabled(sensorID: id))

        adapter.setSensorEnabled(true, sensorID: id)
        XCTAssertTrue(adapter.isEnabled(sensorID: id))

        adapter.setSensorEnabled(false, sensorID: id)
        XCTAssertFalse(adapter.isEnabled(sensorID: id))
    }
}

// MARK: - Recording Sink

private final class RecordingSink: ExternalHRSampleSink, @unchecked Sendable {
    struct Capture {
        let bpm: Int
        let source: String
        let timestamp: Date
    }
    var captured: [Capture] = []

    func ingestExternalSample(bpm: Int, source: String, timestamp: Date) {
        captured.append(Capture(bpm: bpm, source: source, timestamp: timestamp))
    }
}
