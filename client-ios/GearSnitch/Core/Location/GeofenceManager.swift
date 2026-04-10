import Foundation
import CoreLocation
import os

// MARK: - Geofence Manager

/// Handles gym region entry/exit events, identifies which gym was entered,
/// and posts events to the backend API.
final class GeofenceManager {

    private let logger = Logger(subsystem: "com.gearsnitch", category: "GeofenceManager")

    // MARK: - Notifications

    static let gymEntryNotification = Notification.Name("GearSnitch.gymEntry")
    static let gymExitNotification = Notification.Name("GearSnitch.gymExit")

    // MARK: - Region Entry

    /// Handle a region entry event from CoreLocation.
    func handleRegionEntry(_ region: CLCircularRegion) async {
        guard let gymId = GymRegionMonitor.extractGymId(from: region.identifier) else {
            logger.warning("Region entry for unknown region: \(region.identifier)")
            return
        }

        logger.info("Gym entry detected: \(gymId)")

        // Post to backend
        await postGymEvent(gymId: gymId, eventType: "entry", region: region)

        // Post local notification for UI updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: Self.gymEntryNotification,
                object: nil,
                userInfo: ["gymId": gymId]
            )
        }
    }

    // MARK: - Region Exit

    /// Handle a region exit event from CoreLocation.
    func handleRegionExit(_ region: CLCircularRegion) async {
        guard let gymId = GymRegionMonitor.extractGymId(from: region.identifier) else {
            logger.warning("Region exit for unknown region: \(region.identifier)")
            return
        }

        logger.info("Gym exit detected: \(gymId)")

        // Post to backend
        await postGymEvent(gymId: gymId, eventType: "exit", region: region)

        // Post local notification for UI updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: Self.gymExitNotification,
                object: nil,
                userInfo: ["gymId": gymId]
            )
        }
    }

    // MARK: - API

    private func postGymEvent(gymId: String, eventType: String, region: CLCircularRegion) async {
        let body = GymEventBody(
            gymId: gymId,
            eventType: eventType,
            latitude: region.center.latitude,
            longitude: region.center.longitude,
            timestamp: Date()
        )

        do {
            let _: EmptyData = try await APIClient.shared.request(
                APIEndpoint.GymEvents.post(body)
            )
            logger.info("Posted gym \(eventType) event for \(gymId)")
        } catch {
            logger.error("Failed to post gym event: \(error.localizedDescription)")
        }
    }
}

// MARK: - Gym Event Body

struct GymEventBody: Encodable {
    let gymId: String
    let eventType: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

// MARK: - Gym Events Endpoint

extension APIEndpoint {
    enum GymEvents {
        static func post(_ body: GymEventBody) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/gyms/events",
                method: .POST,
                body: body
            )
        }
    }
}
