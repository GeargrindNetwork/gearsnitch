import Foundation

// MARK: - API Response Envelope

/// Standard API response envelope matching the backend contract.
struct ApiResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let meta: ResponseMeta?
    let error: ResponseError?
}

struct ResponseMeta: Decodable {
    let page: Int?
    let limit: Int?
    let total: Int?
    let hasMore: Bool?
}

struct ResponseError: Decodable {
    let code: String?
    let message: String
    let details: [String: String]?
}

// MARK: - Auth Response Types

struct AuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: UserDTO
}

struct UserDTO: Decodable, Identifiable {
    let id: String
    let email: String?
    let displayName: String?
    let avatarURL: String?
    let role: String?
    let referralCode: String?
    let subscriptionTier: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, displayName, avatarURL, role
        case referralCode, subscriptionTier, createdAt
    }
}

// MARK: - Response Decoder

/// Decodes API responses, extracting data from the standard envelope or
/// throwing typed `NetworkError` on failure.
struct ResponseDecoder {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // ISO 8601 with fractional seconds
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: dateString) {
                return date
            }
            // ISO 8601 without fractional seconds
            if let date = ISO8601DateFormatter.standard.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }
        return d
    }()

    /// Decode the full `ApiResponse<T>` envelope and return the inner `T`.
    /// Throws `NetworkError` if the envelope indicates failure or data is nil.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, statusCode: Int) throws -> T {
        // Non-2xx status codes
        guard (200...299).contains(statusCode) else {
            if statusCode == 401 {
                throw NetworkError.unauthorized
            }

            // Try to decode the error envelope
            if let errorResponse = try? decoder.decode(ApiResponse<EmptyData>.self, from: data),
               let error = errorResponse.error {
                throw NetworkError.serverError(
                    code: statusCode,
                    message: error.message
                )
            }

            throw NetworkError.serverError(
                code: statusCode,
                message: "Request failed with status \(statusCode)"
            )
        }

        // Decode the success envelope
        do {
            let envelope = try decoder.decode(ApiResponse<T>.self, from: data)

            guard envelope.success else {
                let message = envelope.error?.message ?? "Unknown server error"
                throw NetworkError.serverError(code: statusCode, message: message)
            }

            guard let result = envelope.data else {
                // Some endpoints return success with no data (e.g. logout)
                // Try to decode T as EmptyData or Void-equivalent
                if T.self == EmptyData.self {
                    // swiftlint:disable:next force_cast
                    return EmptyData() as! T
                }
                throw NetworkError.noData
            }

            return result
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decodingFailed(context: error.localizedDescription)
        }
    }

    /// Decode a raw `ApiResponse<T>` keeping the full envelope.
    static func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data, statusCode: Int) throws -> ApiResponse<T> {
        guard (200...299).contains(statusCode) else {
            if statusCode == 401 { throw NetworkError.unauthorized }
            throw NetworkError.serverError(code: statusCode, message: "HTTP \(statusCode)")
        }

        do {
            return try decoder.decode(ApiResponse<T>.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(context: error.localizedDescription)
        }
    }
}

// MARK: - Empty Data

/// Placeholder for endpoints that return `{ "success": true }` with no data field.
struct EmptyData: Decodable {}

// MARK: - ISO 8601 Formatters

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
