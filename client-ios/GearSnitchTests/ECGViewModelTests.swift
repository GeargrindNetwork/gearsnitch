import XCTest
@testable import GearSnitch

// MARK: - ECG Model Tests
//
// Covers the value types that back the ECG feature after the real-time
// streaming + medical-grade rewrite:
//   - ECGVoltageMeasurement (sample timeline)
//   - ECGRhythm taxonomy and severity mapping
//   - ECGClassification disclaimer text (App Store Guideline 5.1.3)

final class ECGViewModelTests: XCTestCase {

    // MARK: - Rhythm Taxonomy

    func testRhythmTaxonomy_coversAllRequiredCases() {
        // Every case promised in the feature spec must be present.
        let required: Set<ECGRhythm> = [
            .sinusRhythm, .sinusBradycardia, .sinusTachycardia,
            .atrialFibrillation, .atrialFlutter,
            .firstDegreeAVBlock, .mobitzI, .mobitzII, .completeHeartBlock,
            .pvc, .pac, .ventricularTachycardia, .supraventricularTachycardia,
            .indeterminate,
        ]
        let all = Set(ECGRhythm.allCases)
        XCTAssertTrue(required.isSubset(of: all))
    }

    func testRhythmTaxonomy_displayNamesAreNonEmpty() {
        for rhythm in ECGRhythm.allCases {
            XCTAssertFalse(rhythm.displayName.isEmpty, "Display name missing for \(rhythm.rawValue)")
        }
    }

    func testRhythmTaxonomy_severityBuckets() {
        XCTAssertEqual(ECGRhythm.sinusRhythm.severity, .normal)
        XCTAssertEqual(ECGRhythm.atrialFibrillation.severity, .concerning)
        XCTAssertEqual(ECGRhythm.ventricularTachycardia.severity, .concerning)
        XCTAssertEqual(ECGRhythm.completeHeartBlock.severity, .concerning)
        XCTAssertEqual(ECGRhythm.firstDegreeAVBlock.severity, .attention)
        XCTAssertEqual(ECGRhythm.pvc.severity, .attention)
        XCTAssertEqual(ECGRhythm.indeterminate.severity, .unknown)
    }

    // MARK: - Disclaimer (App Store 5.1.3)

    func testDisclaimerText_isExactlyTheAgreedString() {
        // This string is non-negotiable for App Store review — if it changes
        // here, ECGDisclaimerView and the review submission notes must also
        // change in lockstep.
        XCTAssertEqual(
            ECGClassification.disclaimerText,
            "AI-assisted, not a medical diagnosis. Consult a clinician for concerning symptoms."
        )
    }

    // MARK: - Voltage Sample Timeline

    func testVoltageMeasurement_timeOrderingAndCoding() throws {
        let fixture: [ECGVoltageMeasurement] = (0..<10).map { i in
            ECGVoltageMeasurement(time: Double(i) / 512.0, microV: Double(i) * 10)
        }
        for i in 1..<fixture.count {
            XCTAssertGreaterThanOrEqual(fixture[i].time, fixture[i - 1].time)
        }

        // Round-trip through JSON (used by the local history archive).
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(fixture)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let roundTrip = try decoder.decode([ECGVoltageMeasurement].self, from: data)
        XCTAssertEqual(roundTrip.count, fixture.count)
        XCTAssertEqual(roundTrip.first?.microV, 0)
    }

    // MARK: - Sample Rate + Duration

    func testSampleRate_matchesAppleWatch() {
        XCTAssertEqual(ECGSampleRate.hz, 512.0)
        XCTAssertEqual(ECGSampleRate.periodSeconds, 1.0 / 512.0, accuracy: 1e-9)
    }

    func testRecordingDuration_defaults() {
        XCTAssertEqual(ECGRecordingDuration.seconds, 30)
        XCTAssertEqual(ECGRecordingDuration.countdownSeconds, 5)
    }
}
