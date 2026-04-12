import Foundation
import CoreLocation
import os

// MARK: - Tracked Device

struct TrackedDevice: Identifiable, Equatable {
    let id: String
    let name: String
    var coordinate: CLLocationCoordinate2D
    var lastSeenAt: Date
    var signalStrength: Int     // RSSI in dBm
    var batteryPercentage: Int? // 0-100 or nil if unavailable
    var isConnected: Bool

    /// Status for map marker coloring.
    var connectionStatus: TrackedDeviceStatus {
        if isConnected { return .connected }
        let minutesSinceLastSeen = Date().timeIntervalSince(lastSeenAt) / 60
        if minutesSinceLastSeen < 30 { return .recentlySeen }
        return .lost
    }

    static func == (lhs: TrackedDevice, rhs: TrackedDevice) -> Bool {
        lhs.id == rhs.id
    }
}

enum TrackedDeviceStatus {
    case connected      // green
    case recentlySeen   // yellow (<30 min)
    case lost           // red (>30 min)
}

// MARK: - Device Location DTO

struct DeviceLocationDTO: Decodable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let lastSeenAt: String
    let rssi: Int?
    let battery: Int?
    let isConnected: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, latitude, longitude, lastSeenAt, rssi, battery, isConnected
    }
}

// MARK: - ViewModel

@MainActor
final class DeviceMapViewModel: ObservableObject {

    @Published var devices: [TrackedDevice] = []
    @Published var selectedDevice: TrackedDevice?
    @Published var isLoading = false
    @Published var error: String?
    @Published var showDeviceDetail = false

    private let apiClient = APIClient.shared
    private let logger = Logger(subsystem: "com.gearsnitch", category: "DeviceMap")

    /// Timer for auto-polling.
    private var pollTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func startPolling() {
        loadDevices()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard !Task.isCancelled else { break }
                self?.loadDevices()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Data Loading

    func loadDevices() {
        Task {
            if devices.isEmpty {
                isLoading = true
            }
            error = nil

            do {
                let dtos: [DeviceLocationDTO] = try await apiClient.request(
                    APIEndpoint.Devices.locations
                )
                devices = dtos.compactMap { dto in
                    guard let date = parseDate(dto.lastSeenAt) else { return nil }
                    return TrackedDevice(
                        id: dto.id,
                        name: dto.name,
                        coordinate: CLLocationCoordinate2D(
                            latitude: dto.latitude,
                            longitude: dto.longitude
                        ),
                        lastSeenAt: date,
                        signalStrength: dto.rssi ?? -100,
                        batteryPercentage: dto.battery,
                        isConnected: dto.isConnected ?? false
                    )
                }
            } catch {
                // On failure, keep existing local data for offline access
                if devices.isEmpty {
                    self.error = error.localizedDescription
                }
                logger.error("Failed to load device locations: \(error.localizedDescription)")
            }

            isLoading = false
        }
    }

    func selectDevice(_ device: TrackedDevice) {
        selectedDevice = device
        showDeviceDetail = true
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string) {
            return date
        }
        return ISO8601DateFormatter.standard.date(from: string)
    }
}

// MARK: - API Endpoint Extension

extension APIEndpoint.Devices {
    static var locations: APIEndpoint {
        APIEndpoint(path: "/api/v1/devices/locations")
    }
}
