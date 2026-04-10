import Foundation
import CoreLocation
import os

// MARK: - Location Manager

/// Manages location authorization, current location tracking, and gym region monitoring.
@MainActor
final class LocationManager: NSObject, ObservableObject {

    static let shared = LocationManager()

    // MARK: - Published State

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?

    // MARK: - Private Properties

    private let locationManager = CLLocationManager()
    private let geofenceManager: GeofenceManager
    private let logger = Logger(subsystem: "com.gearsnitch", category: "LocationManager")

    /// Maximum monitored regions enforced by iOS.
    private static let maxMonitoredRegions = 20

    // MARK: - Init

    private override init() {
        self.geofenceManager = GeofenceManager()
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false

        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Authorization

    /// Request When In Use location authorization.
    func requestWhenInUse() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request Always location authorization (required for geofencing).
    func requestAlways() {
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - Location Tracking

    /// Start receiving location updates.
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    /// Stop receiving location updates.
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - Gym Region Monitoring

    /// Start monitoring a gym region. Requires Always authorization.
    /// - Parameter gym: The gym to monitor (must include lat/lng/radius).
    func startMonitoring(gym: GymRegion) {
        guard authorizationStatus == .authorizedAlways else {
            logger.warning("Cannot monitor regions without Always authorization")
            return
        }

        let monitoredCount = locationManager.monitoredRegions.count
        guard monitoredCount < Self.maxMonitoredRegions else {
            logger.error("Cannot monitor gym \(gym.name): at max region limit (\(Self.maxMonitoredRegions))")
            return
        }

        let region = GymRegionMonitor.createRegion(from: gym)
        locationManager.startMonitoring(for: region)
        logger.info("Started monitoring gym: \(gym.name) (id: \(gym.id))")
    }

    /// Stop monitoring a specific gym region.
    func stopMonitoring(gym: GymRegion) {
        let regionIdentifier = GymRegionMonitor.regionIdentifier(for: gym.id)

        if let existing = locationManager.monitoredRegions.first(where: { $0.identifier == regionIdentifier }) {
            locationManager.stopMonitoring(for: existing)
            logger.info("Stopped monitoring gym: \(gym.name)")
        }
    }

    /// Stop monitoring all gym regions.
    func stopMonitoringAll() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        logger.info("Stopped monitoring all regions")
    }

    /// Currently monitored region identifiers.
    var monitoredRegionIdentifiers: Set<String> {
        Set(locationManager.monitoredRegions.map(\.identifier))
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            self.logger.info("Location authorization changed: \(manager.authorizationStatus.rawValue)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.currentLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        Task { @MainActor [weak self] in
            self?.logger.info("Entered region: \(region.identifier)")
            await self?.geofenceManager.handleRegionEntry(circularRegion)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        Task { @MainActor [weak self] in
            self?.logger.info("Exited region: \(region.identifier)")
            await self?.geofenceManager.handleRegionExit(circularRegion)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {
        Task { @MainActor [weak self] in
            self?.logger.error("Region monitoring failed for \(region?.identifier ?? "?"): \(error.localizedDescription)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.logger.error("Location manager error: \(error.localizedDescription)")
        }
    }
}
