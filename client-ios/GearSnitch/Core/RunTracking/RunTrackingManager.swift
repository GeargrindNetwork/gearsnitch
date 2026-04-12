import Foundation
import CoreLocation
import os

// MARK: - Run DTOs

struct RunRoutePoint: Codable, Identifiable, Hashable {
    let id: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let altitudeMeters: Double?
    let horizontalAccuracyMeters: Double?
    let speedMetersPerSecond: Double?

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case timestamp
        case altitudeMeters
        case horizontalAccuracyMeters
        case speedMetersPerSecond
    }

    init(
        id: String = UUID().uuidString,
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        altitudeMeters: Double?,
        horizontalAccuracyMeters: Double?,
        speedMetersPerSecond: Double?
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.altitudeMeters = altitudeMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
    }

    init(location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)
        let altitudeMeters = try container.decodeIfPresent(Double.self, forKey: .altitudeMeters)
        let horizontalAccuracyMeters = try container.decodeIfPresent(Double.self, forKey: .horizontalAccuracyMeters)
        let speedMetersPerSecond = try container.decodeIfPresent(Double.self, forKey: .speedMetersPerSecond)

        self.init(
            id: "\(Int(timestamp.timeIntervalSince1970))-\(latitude)-\(longitude)",
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp,
            altitudeMeters: altitudeMeters,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            speedMetersPerSecond: speedMetersPerSecond
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var asLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct RunRouteBounds: Codable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double
}

struct RunRoutePayload: Codable {
    let pointCount: Int
    let bounds: RunRouteBounds?
    let points: [RunRoutePoint]?
}

struct RunDTO: Identifiable, Codable {
    let id: String
    let startedAt: Date
    let endedAt: Date?
    let status: String
    let durationSeconds: Int
    let durationMinutes: Double
    let distanceMeters: Double
    let averagePaceSecondsPerKm: Int?
    let source: String?
    let notes: String?
    let route: RunRoutePayload
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case startedAt
        case endedAt
        case status
        case durationSeconds
        case durationMinutes
        case distanceMeters
        case averagePaceSecondsPerKm
        case source
        case notes
        case route
        case createdAt
        case updatedAt
    }

    var distanceKilometers: Double {
        distanceMeters / 1_000
    }

    var durationString: String {
        RunFormatting.durationString(from: TimeInterval(durationSeconds))
    }

    var distanceString: String {
        RunFormatting.distanceString(from: distanceMeters)
    }

    var paceString: String {
        RunFormatting.paceString(secondsPerKm: averagePaceSecondsPerKm)
    }

    var coordinatePoints: [CLLocationCoordinate2D] {
        route.points?.map(\.coordinate) ?? []
    }
}

struct CreateRunBody: Encodable {
    let startedAt: Date
    let source: String
    let notes: String?
    let routePoints: [RunRoutePoint]
}

struct CompleteRunBody: Encodable {
    let endedAt: Date
    let distanceMeters: Double
    let notes: String?
    let routePoints: [RunRoutePoint]
}

struct ActiveRunSession: Codable {
    var backendRunId: String?
    let startedAt: Date
    var pendingEndAt: Date?
    var routePoints: [RunRoutePoint]
    var distanceMeters: Double
    var notes: String?
    let source: String

    var isEndingPending: Bool {
        pendingEndAt != nil
    }

    var elapsedTime: TimeInterval {
        let endReference = pendingEndAt ?? Date()
        return max(0, endReference.timeIntervalSince(startedAt))
    }

    var durationString: String {
        RunFormatting.durationString(from: elapsedTime)
    }

    var distanceString: String {
        RunFormatting.distanceString(from: distanceMeters)
    }

    var paceSecondsPerKm: Int? {
        guard distanceMeters > 0 else { return nil }
        return Int((elapsedTime / distanceMeters) * 1_000)
    }

    var paceString: String {
        RunFormatting.paceString(secondsPerKm: paceSecondsPerKm)
    }

    var routeSummary: RunRoutePayload {
        RunRoutePayload(
            pointCount: routePoints.count,
            bounds: RunFormatting.computeBounds(points: routePoints),
            points: routePoints
        )
    }
}

enum RunFormatting {
    static func durationString(from duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func distanceString(from meters: Double) -> String {
        let kilometers = meters / 1_000
        if kilometers >= 10 {
            return String(format: "%.1f km", kilometers)
        }
        return String(format: "%.2f km", kilometers)
    }

    static func paceString(secondsPerKm: Int?) -> String {
        guard let secondsPerKm, secondsPerKm > 0 else {
            return "--:-- /km"
        }

        let minutes = secondsPerKm / 60
        let seconds = secondsPerKm % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    static func computeBounds(points: [RunRoutePoint]) -> RunRouteBounds? {
        guard let first = points.first else { return nil }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for point in points {
            minLatitude = min(minLatitude, point.latitude)
            maxLatitude = max(maxLatitude, point.latitude)
            minLongitude = min(minLongitude, point.longitude)
            maxLongitude = max(maxLongitude, point.longitude)
        }

        return RunRouteBounds(
            minLatitude: minLatitude,
            maxLatitude: maxLatitude,
            minLongitude: minLongitude,
            maxLongitude: maxLongitude
        )
    }
}

// MARK: - Run Tracking Manager

@MainActor
final class RunTrackingManager: NSObject, ObservableObject {

    static let shared = RunTrackingManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var activeRun: ActiveRunSession?
    @Published private(set) var isStarting = false
    @Published private(set) var isStopping = false
    @Published var error: String?

    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "com.gearsnitch", category: "RunTracking")
    private let apiClient = APIClient.shared
    private var refreshTimer: Timer?

    private static let persistenceDirectory = "RunTracking"
    private static let persistenceFileName = "active-run.json"

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true

        restoreActiveRun()

        if let activeRun {
            startRefreshTimer()
            if activeRun.pendingEndAt == nil, isAuthorizedForTracking {
                locationManager.startUpdatingLocation()
            }
        }

        Task {
            await recoverRemoteActiveRunIfNeeded()
        }
    }

    var isAuthorizedForTracking: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }

    func startRun() async {
        guard activeRun == nil else { return }

        error = nil

        guard isAuthorizedForTracking else {
            requestPermission()
            error = authorizationStatus == .denied || authorizationStatus == .restricted
                ? "Location permission is required to track a run."
                : "Allow location access, then start the run again."
            return
        }

        isStarting = true

        let draft = ActiveRunSession(
            backendRunId: nil,
            startedAt: Date(),
            pendingEndAt: nil,
            routePoints: [],
            distanceMeters: 0,
            notes: nil,
            source: "ios"
        )

        activeRun = draft
        persistActiveRun()
        startRefreshTimer()
        locationManager.startUpdatingLocation()

        defer { isStarting = false }

        do {
            let created: RunDTO = try await apiClient.request(
                APIEndpoint.Runs.start(
                    CreateRunBody(
                        startedAt: draft.startedAt,
                        source: draft.source,
                        notes: draft.notes,
                        routePoints: []
                    )
                )
            )

            activeRun?.backendRunId = created.id
            persistActiveRun()
        } catch {
            self.error = "Run started locally, but the backend start request failed. Your route will retry on save."
            logger.error("Failed to create backend run: \(error.localizedDescription)")
        }
    }

    func stopRun() async {
        guard var session = activeRun else { return }

        error = nil
        isStopping = true

        if session.pendingEndAt == nil {
            session.pendingEndAt = Date()
        }

        activeRun = session
        persistActiveRun()
        locationManager.stopUpdatingLocation()

        defer { isStopping = false }

        do {
            let runId: String

            if let existingRunId = session.backendRunId {
                runId = existingRunId
            } else {
                let created: RunDTO = try await apiClient.request(
                    APIEndpoint.Runs.start(
                        CreateRunBody(
                            startedAt: session.startedAt,
                            source: session.source,
                            notes: session.notes,
                            routePoints: []
                        )
                    )
                )
                runId = created.id
                activeRun?.backendRunId = created.id
            }

            let endedAt = session.pendingEndAt ?? Date()
            let _: RunDTO = try await apiClient.request(
                APIEndpoint.Runs.complete(
                    id: runId,
                    body: CompleteRunBody(
                        endedAt: endedAt,
                        distanceMeters: session.distanceMeters,
                        notes: session.notes,
                        routePoints: session.routePoints
                    )
                )
            )

            activeRun = nil
            clearPersistedActiveRun()
            stopRefreshTimer()
        } catch {
            self.error = "Run saved locally, but the finish request failed. Retry save when connectivity returns."
            logger.error("Failed to finish run: \(error.localizedDescription)")
        }
    }

    private func recoverRemoteActiveRunIfNeeded() async {
        guard activeRun == nil else { return }

        do {
            let runs: [RunDTO] = try await apiClient.request(APIEndpoint.Runs.list)
            guard let remoteActive = runs.first(where: { $0.status == "active" }) else { return }

            let active = ActiveRunSession(
                backendRunId: remoteActive.id,
                startedAt: remoteActive.startedAt,
                pendingEndAt: nil,
                routePoints: remoteActive.route.points ?? [],
                distanceMeters: remoteActive.distanceMeters,
                notes: remoteActive.notes,
                source: remoteActive.source ?? "ios"
            )

            activeRun = active
            persistActiveRun()
            startRefreshTimer()

            if isAuthorizedForTracking {
                locationManager.startUpdatingLocation()
            }
        } catch {
            logger.error("Failed to recover remote active run: \(error.localizedDescription)")
        }
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func append(location: CLLocation, to session: inout ActiveRunSession) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65 else {
            return
        }

        if let lastPoint = session.routePoints.last, lastPoint.timestamp >= location.timestamp {
            return
        }

        let point = RunRoutePoint(location: location)
        if let previous = session.routePoints.last {
            let increment = point.asLocation.distance(from: previous.asLocation)
            session.distanceMeters = round((session.distanceMeters + increment) * 10) / 10
        }
        session.routePoints.append(point)
    }

    private func persistActiveRun() {
        guard let activeRun else { return }

        do {
            let fileURL = try persistenceURL()
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(activeRun)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Failed to persist active run: \(error.localizedDescription)")
        }
    }

    private func restoreActiveRun() {
        do {
            let fileURL = try persistenceURL()
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            activeRun = try JSONDecoder().decode(ActiveRunSession.self, from: data)
        } catch {
            logger.error("Failed to restore active run: \(error.localizedDescription)")
            clearPersistedActiveRun()
        }
    }

    private func clearPersistedActiveRun() {
        do {
            let fileURL = try persistenceURL()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logger.error("Failed to clear persisted active run: \(error.localizedDescription)")
        }
    }

    private func persistenceURL() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(Self.persistenceDirectory, isDirectory: true)
        return directory.appendingPathComponent(Self.persistenceFileName)
    }
}

// MARK: - CLLocationManagerDelegate

extension RunTrackingManager: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, var session = self.activeRun, session.pendingEndAt == nil else { return }

            for location in locations {
                self.append(location: location, to: &session)
            }

            self.activeRun = session
            self.persistActiveRun()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.error = "Location updates failed: \(error.localizedDescription)"
            self?.logger.error("Location manager failed: \(error.localizedDescription)")
        }
    }
}
