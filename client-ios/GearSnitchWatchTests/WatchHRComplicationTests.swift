import XCTest
import WidgetKit
@testable import GearSnitchWatch

final class WatchHRComplicationTests: XCTestCase {

    func testEntryDisplayTextShowsRoundedBPM() {
        let entry = WatchHRTimelineEntry(
            date: Date(),
            bpm: 142.6,
            sampleAt: Date()
        )
        XCTAssertEqual(entry.displayText, "143")
        XCTAssertFalse(entry.isStale)
    }

    func testEntryDisplayFallsBackWhenNoSample() {
        let entry = WatchHRTimelineEntry(date: Date(), bpm: nil, sampleAt: nil)
        XCTAssertTrue(entry.isStale)
        XCTAssertEqual(entry.displayText, "--")
    }

    func testEntryDisplayFallsBackWhenSampleStale() {
        let stale = Date().addingTimeInterval(-WatchHRTimelineEntry.staleWindow - 10)
        let entry = WatchHRTimelineEntry(date: Date(), bpm: 95, sampleAt: stale)
        XCTAssertTrue(entry.isStale)
        XCTAssertEqual(entry.displayText, "--")
    }

    func testComplicationCenterRoundTripsBPMViaDefaults() {
        let suiteName = "test.watch.complication.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let center = WatchComplicationCenter(suiteName: suiteName)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        center.recordSample(bpm: 101, at: now)

        // Read back via the widget provider's pure function.
        let entry = WatchHRProvider.currentEntry(suiteName: suiteName)
        XCTAssertEqual(entry.bpm, 101)
        XCTAssertEqual(entry.sampleAt?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 0.001)
    }
}
