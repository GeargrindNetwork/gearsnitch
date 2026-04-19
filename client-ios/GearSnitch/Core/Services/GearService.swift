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

extension APIEndpoint {
    enum Gear {
        static var list: APIEndpoint {
            APIEndpoint(path: "/api/v1/gear")
        }

        static func create(_ body: CreateGearBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/gear", method: .POST, body: body)
        }

        static func update(id: String, body: UpdateGearBody) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/gear/\(id)", method: .PATCH, body: body)
        }

        static func logUsage(id: String, amount: Double) -> APIEndpoint {
            APIEndpoint(
                path: "/api/v1/gear/\(id)/log-usage",
                method: .POST,
                body: LogGearUsageBody(amount: amount),
            )
        }

        static func retire(id: String) -> APIEndpoint {
            APIEndpoint(path: "/api/v1/gear/\(id)/retire", method: .POST)
        }
    }
}

// MARK: - Service

/// Typed wrapper around the gear retirement / mileage API.
///
/// All calls are authenticated — `APIClient` injects the current access
/// token. Errors propagate as `NetworkError` for the UI layer to translate.
@MainActor
final class GearService {

    static let shared = GearService()

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
