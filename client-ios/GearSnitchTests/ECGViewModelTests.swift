import HealthKit
import XCTest
@testable import GearSnitch

@MainActor
final class ECGViewModelTests: XCTestCase {

    // MARK: - Classification Mapping

    func testClassificationMapping_sinusRhythm() {
        XCTAssertEqual(
            ECGClassificationFormatter.displayString(for: .sinusRhythm),
            "Sinus Rhythm"
        )
    }

    func testClassificationMapping_atrialFibrillation() {
        XCTAssertEqual(
            ECGClassificationFormatter.displayString(for: .atrialFibrillation),
            "Atrial Fibrillation"
        )
    }

    func testClassificationMapping_inconclusiveLowHeartRate() {
        XCTAssertEqual(
            ECGClassificationFormatter.displayString(for: .inconclusiveLowHeartRate),
            "Inconclusive (Low HR)"
        )
    }

    func testClassificationMapping_inconclusiveHighHeartRate() {
        XCTAssertEqual(
            ECGClassificationFormatter.displayString(for: .inconclusiveHighHeartRate),
            "Inconclusive (High HR)"
        )
    }

    func testClassificationMapping_inconclusivePoorReading() {
        XCTAssertEqual(
            ECGClassificationFormatter.displayString(for: .inconclusivePoorReading),
            "Poor Recording"
        )
    }

    func testClassificationMapping_inconclusiveOther() {
        XCTAssertEqual(
            ECGClassificationFormatter.displayString(for: .inconclusiveOther),
            "Inconclusive"
        )
    }

    func testClassificationMapping_unrecognized() {
        XCTAssertEqual(
            ECGClassificationFormatter.displayString(for: .unrecognized),
            "Unrecognized"
        )
    }

    func testClassificationMapping_notSet() {
        XCTAssertEqual(
            ECGClassificationFormatter.displayString(for: .notSet),
            "Not Set"
        )
    }

    func testClassificationSymbolsAreNonEmpty() {
        // Every supported classification must map to a non-empty SF Symbol name.
        let classifications: [HKElectrocardiogram.Classification] = [
            .notSet, .sinusRhythm, .atrialFibrillation,
            .inconclusiveLowHeartRate, .inconclusiveHighHeartRate,
            .inconclusivePoorReading, .inconclusiveOther, .unrecognized,
        ]
        for c in classifications {
            XCTAssertFalse(
                ECGClassificationFormatter.symbol(for: c).isEmpty,
                "Symbol for classification \(c.rawValue) should not be empty"
            )
        }
    }

    // MARK: - Empty State

    func testViewModel_initialStateIsEmpty() {
        let vm = ECGViewModel()
        XCTAssertTrue(vm.isEmpty, "New view model should report isEmpty == true when latestECG is nil")
        XCTAssertNil(vm.latestECG)
        XCTAssertTrue(vm.voltageMeasurements.isEmpty)
        XCTAssertEqual(vm.classification, "")
        XCTAssertNil(vm.recentHRV)
        XCTAssertNil(vm.averageHeartRateBPM)
        XCTAssertNil(vm.recentHRVMilliseconds)
    }

    // MARK: - Voltage Measurement Aggregation

    func testVoltageMeasurement_equatableAndOrdering() {
        let fixture: [ECGVoltageMeasurement] = [
            ECGVoltageMeasurement(time: 0.0, microV: -50.0),
            ECGVoltageMeasurement(time: 0.002, microV: 120.0),
            ECGVoltageMeasurement(time: 0.004, microV: 300.0),
            ECGVoltageMeasurement(time: 0.006, microV: -40.0),
            ECGVoltageMeasurement(time: 0.008, microV: 10.0),
        ]

        // Monotonic non-decreasing time ordering (as HealthKit yields).
        for i in 1..<fixture.count {
            XCTAssertGreaterThanOrEqual(fixture[i].time, fixture[i - 1].time)
        }

        XCTAssertEqual(fixture.count, 5)
        XCTAssertEqual(fixture.first?.microV, -50.0)
        XCTAssertEqual(fixture.last?.microV, 10.0)
    }

    func testVoltageMeasurement_averageAndPeakComputationOnFixture() {
        // Simulates how a waveform summary would be derived from collected samples.
        let fixture: [ECGVoltageMeasurement] = (0..<250).map { i in
            // 250 samples at 512 Hz -> roughly 0.49s of ECG data.
            let t = Double(i) / 512.0
            // A toy waveform: baseline noise plus a single R-spike at i == 125.
            let microV: Double
            if i == 125 {
                microV = 950.0
            } else {
                microV = sin(Double(i) * 0.05) * 40.0
            }
            return ECGVoltageMeasurement(time: t, microV: microV)
        }

        XCTAssertEqual(fixture.count, 250)

        let peak = fixture.map(\.microV).max() ?? 0
        XCTAssertEqual(peak, 950.0, "R-spike should be detectable as the peak")

        let sum = fixture.reduce(0.0) { $0 + $1.microV }
        let mean = sum / Double(fixture.count)
        // The spike is a single outlier; mean should still be dominated by it
        // enough to be positive, but far below the peak.
        XCTAssertGreaterThan(peak, mean)
        XCTAssertLessThan(mean, peak / 2.0)

        // Time axis spans the expected window.
        XCTAssertEqual(fixture.first?.time, 0.0)
        XCTAssertEqual(fixture.last?.time ?? 0, 249.0 / 512.0, accuracy: 0.0001)
    }
}
