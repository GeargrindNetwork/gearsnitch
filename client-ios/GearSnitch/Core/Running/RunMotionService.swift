import Foundation
import Combine
import CoreMotion
import os

// MARK: - RunMotionService (Backlog item #18)
//
// Thin wrapper around `CMMotionManager` for the inactivity detector.
// Kept separate from `RunTrackingManager` so it can be mocked in tests
// and so the CoreMotion integration is opt-in — we only pull device
// motion while a run is active.
//
// The service publishes `CMDeviceMotion` samples at 10Hz and stops
// the sensor as soon as the caller cancels its subscription / calls
// `stop()`. If device motion is unavailable (simulator, older iPad
// without a gyroscope) the publisher simply never emits.

@MainActor
final class RunMotionService {

    static let shared = RunMotionService()

    private let manager = CMMotionManager()
    private let subject = PassthroughSubject<CMDeviceMotion, Never>()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "RunMotionService")

    /// 10Hz is enough to average out jitter without burning battery.
    private let updateInterval: TimeInterval = 0.1

    /// Public publisher that callers subscribe to. Lives for the
    /// lifetime of the service; start/stop just gate whether samples
    /// are flowing.
    var publisher: AnyPublisher<CMDeviceMotion, Never> {
        subject.eraseToAnyPublisher()
    }

    func start() {
        guard manager.isDeviceMotionAvailable else {
            logger.info("Device motion unavailable — inactivity detector will fall back to GPS-only.")
            return
        }
        guard !manager.isDeviceMotionActive else { return }

        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error {
                self?.logger.error("Device motion update failed: \(error.localizedDescription)")
                return
            }
            guard let motion else { return }
            self?.subject.send(motion)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }
}
