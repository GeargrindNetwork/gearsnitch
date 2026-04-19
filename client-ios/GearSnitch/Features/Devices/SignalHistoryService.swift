import Foundation

// MARK: - DTOs

/// Single bucket from `GET /api/v1/devices/:id/rssi/history`. Each
/// bucket represents an equal-width slice of the requested `windowHours`
/// window, averaged across the RSSI samples that landed in it.
struct SignalHistoryBucket: Decodable, Identifiable {
    /// Bucket start timestamp. `id` uses this so SwiftUI's `ForEach`
    /// stays stable across refreshes.
    let ts: Date
    let avgRssi: Double
    let count: Int

    var id: Date { ts }
}

/// Full response envelope of `GET /api/v1/devices/:id/rssi/history`.
struct SignalHistoryResponse: Decodable {
    let deviceId: String
    let windowHours: Int
    let buckets: [SignalHistoryBucket]
    /// 7-day average (limited by the server's TTL retention). `nil` if
    /// we have no samples at all for the device.
    let lifetimeAvg: Double?
    /// Signed delta in dBm: `thisWeekAvg - priorWeekAvg`. Positive
    /// means signal improved. `nil` when either week has zero samples.
    let weekOverWeekDelta: Double?
}

// MARK: - Service

/// Thin wrapper around `GET /api/v1/devices/:id/rssi/history` so the
/// view model can depend on a protocol and tests can stub the network.
/// Backlog item #19.
protocol SignalHistoryServicing {
    func fetchHistory(
        deviceId: String,
        windowHours: Int,
        buckets: Int
    ) async throws -> SignalHistoryResponse
}

struct SignalHistoryService: SignalHistoryServicing {
    static let shared = SignalHistoryService()

    func fetchHistory(
        deviceId: String,
        windowHours: Int = 24,
        buckets: Int = 60
    ) async throws -> SignalHistoryResponse {
        let endpoint = APIEndpoint(
            path: "/api/v1/devices/\(deviceId)/rssi/history",
            method: .GET,
            queryItems: [
                URLQueryItem(name: "windowHours", value: "\(windowHours)"),
                URLQueryItem(name: "buckets", value: "\(buckets)"),
            ]
        )
        return try await APIClient.shared.request(endpoint)
    }
}
