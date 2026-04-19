import Foundation

// MARK: - Gear DTOs

/// Mirrors the shape returned by `GET /api/v1/gear` on the API side. See
/// `api/src/modules/gear/routes.ts` `serializeComponent`.
struct GearComponentDTO: Identifiable, Decodable, Equatable {
    let id: String
    let userId: String?
    let deviceId: String?
    let name: String
    let kind: String
    let unit: String
    let lifeLimit: Double
    let warningThreshold: Double
    let currentValue: Double
    let usagePct: Double
    let status: String
    let retiredAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, deviceId, name, kind, unit
        case lifeLimit, warningThreshold, currentValue, usagePct
        case status, retiredAt, createdAt, updatedAt
    }

    /// Color-coded status band for the gear list, in lockstep with the
    /// design system colors (green / yellow / orange / red).
    var usageBand: GearUsageBand {
        GearUsageBand.fromUsagePct(usagePct)
    }

    var isRetired: Bool {
        status == "retired"
    }

    /// Human-readable usage label (e.g. "142.3 miles", "08:42 hours").
    var usageLabel: String {
        switch unit {
        case "miles":
            return String(format: "%.1f mi", currentValue)
        case "km":
            return String(format: "%.1f km", currentValue)
        case "hours":
            return String(format: "%.1f hr", currentValue)
        case "sessions":
            let int = Int(currentValue.rounded())
            return "\(int) session\(int == 1 ? "" : "s")"
        default:
            return String(format: "%.1f", currentValue)
        }
    }
}

/// Usage band — drives the gear list color coding.
///
/// Pure enum so it can be unit-tested without touching SwiftUI.
enum GearUsageBand: String, Equatable {
    case healthy   // < 70%
    case caution   // 70-85%
    case warning   // 85-100%
    case retired   // >= 100%

    static func fromUsagePct(_ pct: Double) -> GearUsageBand {
        if pct >= 1.0 {
            return .retired
        }
        if pct >= 0.85 {
            return .warning
        }
        if pct >= 0.70 {
            return .caution
        }
        return .healthy
    }
}

// MARK: - Request Bodies

struct CreateGearBody: Encodable {
    let name: String
    let kind: String
    let unit: String
    let lifeLimit: Double
    let warningThreshold: Double?
    let currentValue: Double?
    let deviceId: String?
}

struct UpdateGearBody: Encodable {
    let name: String?
    let kind: String?
    let unit: String?
    let lifeLimit: Double?
    let warningThreshold: Double?
    let currentValue: Double?
    let status: String?
    let deviceId: String?
}

struct LogGearUsageBody: Encodable {
    let amount: Double
}

/// Response of `POST /gear/:id/log-usage` — reports whether the increment
/// crossed the warning or retirement threshold (so the UI can surface a
/// confirmation banner without waiting for the push).
struct LogGearUsageResponse: Decodable {
    let component: GearComponentDTO
    let crossedWarning: Bool
    let crossedRetirement: Bool
}

// MARK: - Endpoints
// The `APIEndpoint.Gear` enum lives in `Core/Network/APIEndpoint.swift`.
// The CRUD methods below are added there so all endpoint declarations stay
// in a single file.

// MARK: - Service

/// Typed wrapper around the gear retirement / mileage API.
///
/// All calls are authenticated — `APIClient` injects the current access
/// token. Errors propagate as `NetworkError` for the UI layer to translate.
@MainActor
final class GearService {

    // `nonisolated(unsafe)` so callers in nonisolated contexts (e.g. the
    // default-argument expression on init signatures — SwiftUI viewmodel
    // init is evaluated nonisolated) can reference it without Swift 6
    // "main actor-isolated static property" diagnostics. Safe because the
    // singleton is initialized once at process start before any
    // cross-thread access could happen.
    nonisolated(unsafe) static let shared = GearService()

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func list() async throws -> [GearComponentDTO] {
        try await apiClient.request(APIEndpoint.Gear.list)
    }

    func create(_ body: CreateGearBody) async throws -> GearComponentDTO {
        try await apiClient.request(APIEndpoint.Gear.create(body))
    }

    func update(id: String, body: UpdateGearBody) async throws -> GearComponentDTO {
        try await apiClient.request(APIEndpoint.Gear.update(id: id, body: body))
    }

    func logUsage(id: String, amount: Double) async throws -> LogGearUsageResponse {
        try await apiClient.request(APIEndpoint.Gear.logUsage(id: id, amount: amount))
    }

    func retire(id: String) async throws -> GearComponentDTO {
        try await apiClient.request(APIEndpoint.Gear.retire(id: id))
    }
}
