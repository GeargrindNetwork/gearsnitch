import XCTest
import CoreLocation
@testable import GearSnitch

// MARK: - InactivityDetectorTests (Backlog item #18)
//
// Drives the detector deterministically via `ingest(...at:)` /
// `tick(now:)` — no real wall-clock waits. Each test exercises one
// signal (GPS speed, accel magnitude, GPS cluster) or the bypass
// behavior when the feature is disabled.

@MainActor
final class InactivityDetectorTests: XCTestCase {

    private let origin = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Helpers

    private func makeDetector() -> InactivityDetector {
        let d = InactivityDetector()
        // Tighten the cluster window so a 2-point cluster test is
        // easy to express, and keep the default 60s inactivity
        // window so assertions line up with the spec.
        return d
    }

    private func slowLocation(at offset: TimeInterval, coord: CLLocationCoordinate2D? = nil, speed: Double = 0.1) -> CLLocation {
        CLLocation(
            coordinate: coord ?? origin,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: speed,
            timestamp: start.addingTimeInterval(offset)
        )
    }

    private func fastLocation(at offset: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: origin.latitude + 0.001 * offset,
                longitude: origin.longitude
            ),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 3.0, // ~10.8 km/h — definitely running
            timestamp: start.addingTimeInterval(offset)
        )
    }

    // MARK: - GPS speed signal

    func testLowSpeedFor60SecondsTransitionsToPaused() {
        let detector = makeDetector()
        XCTAssertEqual(detector.state, .active)

        // First low-speed sample at t=0.
        detector.ingest(location: slowLocation(at: 0), at: start)
        XCTAssertEqual(detector.state, .active, "One slow fix is not enough.")

        // A tick just under the window should still be active.
        detector.tick(now: start.addingTimeInterval(59))
        XCTAssertEqual(detector.state, .active)

        // At exactly 60s we flip.
        detector.tick(now: start.addingTimeInterval(60))
        XCTAssertEqual(detector.state, .paused)
    }

    func testFastFixAfterPausedResumesImmediately() {
        let detector = makeDetector()

        detector.ingest(location: slowLocation(at: 0), at: start)
        detector.tick(now: start.addingTimeInterval(65))
        XCTAssertEqual(detector.state, .paused)

        // A single fast fix flips us back to active.
        detector.ingest(location: fastLocation(at: 66), at: start.addingTimeInterval(66))
        XCTAssertEqual(detector.state, .active)
    }

    // MARK: - Accelerometer signal

    func testLowAccelerationFor60SecondsTransitionsToPaused() {
        let detector = makeDetector()

        detector.ingest(accelerationMagnitudeG: 0.01, at: start)
        XCTAssertEqual(detector.state, .active)

        detector.ingest(accelerationMagnitudeG: 0.01, at: start.addingTimeInterval(30))
        XCTAssertEqual(detector.state, .active)

        detector.ingest(accelerationMagnitudeG: 0.01, at: start.addingTimeInterval(61))
        XCTAssertEqual(detector.state, .paused)
    }

    func testHighAccelerationClearsLowMotion() {
        let detector = makeDetector()

        detector.ingest(accelerationMagnitudeG: 0.01, at: start)
        // Big kick — user started moving.
        detector.ingest(accelerationMagnitudeG: 0.3, at: start.addingTimeInterval(20))

        // Even after 60s from t=0, we should still be active because
        // the low-motion timer was reset at t=20.
        detector.tick(now: start.addingTimeInterval(61))
        XCTAssertEqual(detector.state, .active)
    }

    // MARK: - GPS cluster signal

    func testThreeClusteredFixesWithin10mTransitionsToPausedAfter60s() {
        let detector = makeDetector()

        let a = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
        let b = CLLocationCoordinate2D(latitude: origin.latitude + 0.00002, longitude: origin.longitude) // ~2m
        let c = CLLocationCoordinate2D(latitude: origin.latitude + 0.00005, longitude: origin.longitude) // ~5m

        // Use a speed above the threshold so we're *only* testing
        // the cluster signal, not the speed signal.
        let speed = detector.minSpeedMPS + 1.0

        detector.ingest(location: slowLocation(at: 0, coord: a, speed: speed), at: start)
        detector.ingest(location: slowLocation(at: 1, coord: b, speed: speed), at: start.addingTimeInterval(1))
        detector.ingest(location: slowLocation(at: 2, coord: c, speed: speed), at: start.addingTimeInterval(2))

        // The cluster signal starts counting from the third fix
        // (t=2), so we tick 60s past that, not past t=0.
        detector.tick(now: start.addingTimeInterval(62))
        XCTAssertEqual(detector.state, .paused)
    }

    // MARK: - Disabled bypass

    func testDisabledDetectorNeverTransitionsToPaused() {
        let detector = makeDetector()
        detector.setEnabled(false)

        detector.ingest(location: slowLocation(at: 0), at: start)
        detector.ingest(accelerationMagnitudeG: 0.001, at: start.addingTimeInterval(10))
        detector.tick(now: start.addingTimeInterval(1_000))

        XCTAssertEqual(detector.state, .active)
    }

    func testReEnablingAfterDisableStartsFresh() {
        let detector = makeDetector()

        detector.ingest(location: slowLocation(at: 0), at: start)
        detector.tick(now: start.addingTimeInterval(30))

        detector.setEnabled(false)
        XCTAssertEqual(detector.state, .active)

        detector.setEnabled(true)
        // Even though real time has advanced well past 60s from the
        // original slow fix, the accumulated low-motion state was
        // reset — we need another 60s of low motion from here.
        detector.tick(now: start.addingTimeInterval(61))
        XCTAssertEqual(detector.state, .active)
    }

    // MARK: - Force resume

    func testForceResumeSuppressesReEntryFor30s() {
        let detector = makeDetector()

        detector.ingest(location: slowLocation(at: 0), at: start)
        detector.tick(now: start.addingTimeInterval(60))
        XCTAssertEqual(detector.state, .paused)

        detector.forceResume(now: start.addingTimeInterval(60))
        XCTAssertEqual(detector.state, .active)

        // Low-motion fixes within the suppression window don't flip
        // us back to paused.
        detector.ingest(location: slowLocation(at: 65), at: start.addingTimeInterval(65))
        detector.tick(now: start.addingTimeInterval(80))
        XCTAssertEqual(detector.state, .active, "Force-resume suppression should hold for 30s.")
    }
}
