import Foundation
import Combine
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

    // MARK: - Auto-pause (Backlog item #18)
    //
    // When the inactivity detector flips to `.paused` we stamp
    // `pausedAt` with the transition time. On resume we roll that
    // delta into `accumulatedPausedSeconds` and clear `pausedAt`.
    // `elapsedTime` subtracts paused time so the pace average stays
    // honest — this is the whole point of the feature.
    var pausedAt: Date?
    var accumulatedPausedSeconds: TimeInterval

    // Custom CodingKeys so older persisted sessions (without the
    // two pause fields) still decode cleanly after the app updates.
    private enum CodingKeys: String, CodingKey {
        case backendRunId
        case startedAt
        case pendingEndAt
        case routePoints
        case distanceMeters
        case notes
        case source
        case pausedAt
        case accumulatedPausedSeconds
    }

    init(
        backendRunId: String?,
        startedAt: Date,
        pendingEndAt: Date?,
        routePoints: [RunRoutePoint],
        distanceMeters: Double,
        notes: String?,
        source: String,
        pausedAt: Date? = nil,
        accumulatedPausedSeconds: TimeInterval = 0
    ) {
        self.backendRunId = backendRunId
        self.startedAt = startedAt
        self.pendingEndAt = pendingEndAt
        self.routePoints = routePoints
        self.distanceMeters = distanceMeters
        self.notes = notes
        self.source = source
        self.pausedAt = pausedAt
        self.accumulatedPausedSeconds = accumulatedPausedSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.backendRunId = try c.decodeIfPresent(String.self, forKey: .backendRunId)
        self.startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.pendingEndAt = try c.decodeIfPresent(Date.self, forKey: .pendingEndAt)
        self.routePoints = try c.decode([RunRoutePoint].self, forKey: .routePoints)
        self.distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.source = try c.decode(String.self, forKey: .source)
        self.pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
        self.accumulatedPausedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .accumulatedPausedSeconds) ?? 0
    }

    var isEndingPending: Bool {
        pendingEndAt != nil
    }

    /// True while the inactivity detector has the run auto-paused.
    /// View code uses this to show the "Auto-paused" banner and to
    /// freeze the elapsed-time display.
    var isPaused: Bool {
        pausedAt != nil
    }

    /// Elapsed time minus paused time — the value that drives the
    /// pace calculation. While paused, the clock freezes.
    var elapsedTime: TimeInterval {
        let endReference = pendingEndAt ?? Date()
        let gross = max(0, endReference.timeIntervalSince(startedAt))
        let currentPauseDelta: TimeInterval = {
            guard let pausedAt, pendingEndAt == nil else { return 0 }
            return max(0, Date().timeIntervalSince(pausedAt))
        }()
        let paused = accumulatedPausedSeconds + currentPauseDelta
        return max(0, gross - paused)
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

    // MARK: - Rolling Pace (Backlog item #21)

    /// Compute the user's current pace over the last `windowSeconds`
    /// of GPS fixes, in seconds-per-mile. Returns `nil` if we don't
    /// have enough data (or the runner is stationary). The pace coach
    /// uses this (not `paceSecondsPerKm`) so short spikes / pauses
    /// don't trigger false "speed up" buzzes right after a traffic
    /// light.
    func rollingPaceSecondsPerMile(
        windowSeconds: TimeInterval = 30,
        now: Date = Date()
    ) -> Int? {
        guard !isPaused, routePoints.count >= 2 else { return nil }

        let cutoff = now.addingTimeInterval(-windowSeconds)
        let window = routePoints.filter { $0.timestamp >= cutoff }
        guard window.count >= 2 else { return nil }

        var distanceMeters = 0.0
        for i in 1..<window.count {
            distanceMeters += window[i].asLocation.distance(from: window[i - 1].asLocation)
        }
        let firstTimestamp = window.first?.timestamp ?? now
        let lastTimestamp  = window.last?.timestamp ?? now
        let elapsed = max(0, lastTimestamp.timeIntervalSince(firstTimestamp))
        guard elapsed > 0, distanceMeters > 0.5 else { return nil }

        let metersPerMile = 1_609.344
        let secondsPerMile = (elapsed / distanceMeters) * metersPerMile
        return Int(secondsPerMile.rounded())
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

    // MARK: - Auto-pause (Backlog item #18)
    //
    // The inactivity detector watches GPS + motion for a 60s stretch
    // of "not moving" and flips `state` to `.paused`. We subscribe to
    // that state here and call `pause()` / `resume()` which flip the
    // session's `pausedAt` field. `autoPauseBanner` is a one-shot flag
    // the active-run view binds to for its "Auto-paused" indicator.

    let inactivityDetector = InactivityDetector()
    private let motionService = RunMotionService.shared
    private let autoPausePreferences = RunAutoPausePreferences()
    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    private var detectorStateSub: AnyCancellable?

    /// Bannered state: `true` briefly after the detector auto-pauses
    /// or auto-resumes. The ActiveRunView shows a transient banner and
    /// clears this on its own 3s timer.
    @Published var autoPauseBanner: AutoPauseBannerState?

    enum AutoPauseBannerState: Equatable {
        case paused
        case resumed
    }

    // MARK: - Pace Coach (Backlog item #21)
    //
    // The pace coach evaluates on every 1Hz tick of `refreshTimer` and:
    //   1. Updates `paceStatus` for the ActiveRunView chip.
    //   2. If the user is off-pace and the 30s cooldown has elapsed,
    //      forwards a haptic to the Watch AND (when cadence-tone is
    //      enabled + headphones are connected) keeps the tone player
    //      in sync with the user's target cadence.

    private let paceCoach = RunPaceCoach()
    private var paceCoachPreferences = RunPaceCoachPreferences()

    /// Current pace-coach chip state. `nil` until the first off-pace
    /// / on-pace evaluation has happened.
    @Published private(set) var paceStatus: PaceStatus?

    /// User-editable target pace (seconds per mile). Mirrors
    /// `RunPaceCoachPreferences.targetPaceSecondsPerMile` but is
    /// exposed as a `@Published` so the `ActiveRunView` can bind a
    /// mid-run editor to it.
    @Published var targetPaceSecondsPerMile: Int = RunPaceCoachPreferences.fallbackPaceSecondsPerMile {
        didSet {
            paceCoachPreferences.targetPaceSecondsPerMile = targetPaceSecondsPerMile
        }
    }

    /// User-editable target cadence in SPM.
    @Published var targetCadenceSPM: Int = RunPaceCoachPreferences.fallbackCadenceSPM {
        didSet {
            paceCoachPreferences.targetCadenceSPM = targetCadenceSPM
            // Only re-tune if the tone player is already running,
            // otherwise we'd start it prematurely (cadence is OPT-IN).
            if RunPaceCadenceTonePlayer.shared.isRunning {
                RunPaceCadenceTonePlayer.shared.start(spm: targetCadenceSPM)
            }
        }
    }

    /// Whether the headphone cadence tone is enabled (OPT-IN). Setter
    /// starts/stops the tone player immediately so the toggle acts
    /// like a play/pause button while the run is active.
    @Published var cadenceToneEnabled: Bool = false {
        didSet {
            paceCoachPreferences.cadenceEnabled = cadenceToneEnabled
            if cadenceToneEnabled, activeRun != nil {
                RunPaceCadenceTonePlayer.shared.start(spm: targetCadenceSPM)
            } else {
                RunPaceCadenceTonePlayer.shared.stop()
            }
        }
    }

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

        // Backlog item #21 — hydrate pace-coach state from
        // UserDefaults on launch so the user's chosen target pace /
        // cadence / opt-in persists across sessions.
        targetPaceSecondsPerMile = paceCoachPreferences.targetPaceSecondsPerMile
        targetCadenceSPM = paceCoachPreferences.targetCadenceSPM
        cadenceToneEnabled = paceCoachPreferences.cadenceEnabled

        // Backlog item #18 — wire the inactivity detector to the
        // manager's location + motion streams. We honor the user
        // setting (default ON) here; the detector itself refuses to
        // flip state when disabled.
        inactivityDetector.setEnabled(autoPausePreferences.isEnabled)
        observeDetectorState()

        if let activeRun {
            startRefreshTimer()
            if activeRun.pendingEndAt == nil, isAuthorizedForTracking {
                locationManager.startUpdatingLocation()
                startInactivityDetector()
            }
        }

        Task {
            await recoverRemoteActiveRunIfNeeded()
        }
    }

    /// Called by the settings toggle. Immediately enables / disables
    /// the detector and updates the persisted preference.
    func setAutoPauseEnabled(_ enabled: Bool) {
        autoPausePreferences.isEnabled = enabled
        inactivityDetector.setEnabled(enabled)
        if !enabled, activeRun?.isPaused == true {
            // If we disable while currently auto-paused, resume so the
            // user isn't stuck on a frozen timer.
            resume()
        }
    }

    private func observeDetectorState() {
        detectorStateSub?.cancel()
        detectorStateSub = inactivityDetector.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .paused:
                    self.pause()
                case .active:
                    if self.activeRun?.isPaused == true {
                        self.resume()
                    }
                }
            }
    }

    private func startInactivityDetector() {
        motionService.start()
        inactivityDetector.start(
            locationPublisher: locationSubject.eraseToAnyPublisher(),
            motionPublisher: motionService.publisher
        )
    }

    private func stopInactivityDetector() {
        inactivityDetector.stop()
        motionService.stop()
        inactivityDetector.reset()
    }

    /// Auto-pause the run. Idempotent — does nothing when there's no
    /// active run or it's already paused.
    func pause() {
        guard var session = activeRun, !session.isPaused, session.pendingEndAt == nil else { return }
        session.pausedAt = Date()
        activeRun = session
        persistActiveRun()
        autoPauseBanner = .paused
        logger.info("Run auto-paused (inactivity detector).")
    }

    /// Resume a paused run. Idempotent. Rolls the pause delta into
    /// `accumulatedPausedSeconds` so `elapsedTime` stays honest.
    func resume() {
        guard var session = activeRun, let pausedAt = session.pausedAt else { return }
        let delta = max(0, Date().timeIntervalSince(pausedAt))
        session.accumulatedPausedSeconds += delta
        session.pausedAt = nil
        activeRun = session
        persistActiveRun()
        autoPauseBanner = .resumed
        logger.info("Run resumed after \(delta)s pause.")
    }

    /// User tapped the banner / manual-resume affordance. Forces
    /// state back to active and suppresses re-pause for 30s so they
    /// aren't immediately auto-paused again.
    func forceResume() {
        inactivityDetector.forceResume()
        resume()
    }

    /// Called by the banner view after it finishes its 3s display.
    func clearAutoPauseBanner() {
        autoPauseBanner = nil
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
        startInactivityDetector()

        // Backlog item #21 — reset coach cooldown so the previous
        // session's last-fired timestamp doesn't carry over, and
        // start the cadence tone if the user opted in.
        paceCoach.reset()
        paceStatus = nil
        if cadenceToneEnabled {
            RunPaceCadenceTonePlayer.shared.start(spm: targetCadenceSPM)
        }

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

        // If we were auto-paused when the user stopped the run, roll
        // the final pause delta in so the stored duration is correct.
        if let pausedAt = session.pausedAt {
            let delta = max(0, (session.pendingEndAt ?? Date()).timeIntervalSince(pausedAt))
            session.accumulatedPausedSeconds += delta
            session.pausedAt = nil
        }

        activeRun = session
        persistActiveRun()
        locationManager.stopUpdatingLocation()
        stopInactivityDetector()
        autoPauseBanner = nil

        // Backlog item #21 — tear down the pace coach on run stop so
        // we release the audio session (unblocks the user's music
        // ducking) and clear the UI chip.
        RunPaceCadenceTonePlayer.shared.stop()
        paceCoach.reset()
        paceStatus = nil

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
                startInactivityDetector()
            }
        } catch {
            logger.error("Failed to recover remote active run: \(error.localizedDescription)")
        }
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Give the detector a chance to flip to paused even
                // when no fresh GPS fix has arrived in a while.
                self.inactivityDetector.tick()
                // Backlog item #21: run the pace-coach evaluation
                // every tick so the chip + haptic stay current.
                self.tickPaceCoach()
                self.objectWillChange.send()
            }
        }
    }

    /// Feed the pace coach one evaluation tick. Public for testability.
    func tickPaceCoach(now: Date = Date()) {
        guard let activeRun, activeRun.pendingEndAt == nil, !activeRun.isPaused else {
            // Inactive or paused — don't publish a stale status.
            return
        }
        let currentPace = activeRun.rollingPaceSecondsPerMile(now: now)
        let decision = paceCoach.evaluate(
            currentPaceSecondsPerMile: currentPace,
            targetPaceSecondsPerMile: targetPaceSecondsPerMile,
            driftThresholdPct: paceCoachPreferences.driftThresholdPct,
            now: now
        )
        paceStatus = decision.status

        if let haptic = decision.haptic {
            WatchSyncManager.shared.sendPaceCoachHaptic(kind: haptic.rawValue)
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
                // Forward every fix to the inactivity detector — we
                // want it to see the full stream, not the
                // accuracy-filtered subset used for the polyline.
                self.locationSubject.send(location)

                // Skip route-point accumulation while auto-paused so
                // distance doesn't drift from GPS noise at a stand
                // (traffic light, shoelace, etc).
                if !session.isPaused {
                    self.append(location: location, to: &session)
                }
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
