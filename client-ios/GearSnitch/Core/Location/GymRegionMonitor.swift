import Foundation
import CoreLocation

// MARK: - Gym Region

/// Data needed to create a monitored CLCircularRegion for a gym.
struct GymRegion {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Radius in meters. Default 150m.
    let radiusMeters: Double

    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 150
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }
}

// MARK: - Gym Region Monitor

/// Creates and manages CLCircularRegion instances from gym data.
enum GymRegionMonitor {

    /// Prefix used for all gym region identifiers.
    private static let regionPrefix = "gearsnitch.gym."

    /// Maximum radius allowed by iOS (approximately 300km, but we cap lower).
    private static let maxRadius: CLLocationDistance = 500
    /// Minimum radius for meaningful geofencing.
    private static let minRadius: CLLocationDistance = 50
    /// Default radius in meters.
    static let defaultRadius: CLLocationDistance = 150

    // MARK: - Create Region

    /// Create a `CLCircularRegion` from gym data with configurable radius.
    /// Clamps radius to [50m, 500m] for practical geofencing accuracy.
    static func createRegion(from gym: GymRegion) -> CLCircularRegion {
        let center = CLLocationCoordinate2D(
            latitude: gym.latitude,
            longitude: gym.longitude
        )

        let clampedRadius = min(max(gym.radiusMeters, minRadius), maxRadius)

        let region = CLCircularRegion(
            center: center,
            radius: clampedRadius,
            identifier: regionIdentifier(for: gym.id)
        )

        region.notifyOnEntry = true
        region.notifyOnExit = true

        return region
    }

    // MARK: - Identifier Helpers

    /// Generate a unique region identifier for a gym ID.
    static func regionIdentifier(for gymId: String) -> String {
        "\(regionPrefix)\(gymId)"
    }

    /// Extract the gym ID from a region identifier, or nil if the identifier
    /// does not match the expected format.
    static func extractGymId(from regionIdentifier: String) -> String? {
        guard regionIdentifier.hasPrefix(regionPrefix) else { return nil }
        let gymId = String(regionIdentifier.dropFirst(regionPrefix.count))
        return gymId.isEmpty ? nil : gymId
    }
}
