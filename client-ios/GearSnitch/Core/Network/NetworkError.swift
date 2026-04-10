import Foundation

/// All API and network errors surfaced by the networking layer.
enum NetworkError: LocalizedError, Equatable {
    case unauthorized
    case serverError(code: Int, message: String)
    case networkUnavailable
    case decodingFailed(context: String)
    case tokenRefreshFailed
    case invalidURL
    case noData
    case unknown(statusCode: Int?)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .serverError(let code, let message):
            return "Server error \(code): \(message)"
        case .networkUnavailable:
            return "No network connection. Please check your internet and try again."
        case .decodingFailed(let context):
            return "Failed to process server response: \(context)"
        case .tokenRefreshFailed:
            return "Unable to refresh your session. Please sign in again."
        case .invalidURL:
            return "Invalid request URL."
        case .noData:
            return "The server returned an empty response."
        case .unknown(let statusCode):
            if let code = statusCode {
                return "An unexpected error occurred (HTTP \(code))."
            }
            return "An unexpected error occurred."
        }
    }

    /// Whether this error should trigger a sign-out flow.
    var requiresReauthentication: Bool {
        switch self {
        case .unauthorized, .tokenRefreshFailed:
            return true
        default:
            return false
        }
    }

    static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.networkUnavailable, .networkUnavailable): return true
        case (.tokenRefreshFailed, .tokenRefreshFailed): return true
        case (.invalidURL, .invalidURL): return true
        case (.noData, .noData): return true
        case (.serverError(let lc, let lm), .serverError(let rc, let rm)):
            return lc == rc && lm == rm
        case (.decodingFailed(let l), .decodingFailed(let r)):
            return l == r
        case (.unknown(let l), .unknown(let r)):
            return l == r
        default:
            return false
        }
    }
}
