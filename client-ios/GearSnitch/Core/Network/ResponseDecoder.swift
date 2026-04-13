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
    let refreshToken: String?
    let user: UserDTO?

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case accessTokenSnake = "access_token"
        case refreshToken
        case refreshTokenSnake = "refresh_token"
        case token
        case user
        case profile
        case tokens
    }

    private enum TokenCodingKeys: String, CodingKey {
        case accessToken
        case accessTokenSnake = "access_token"
        case refreshToken
        case refreshTokenSnake = "refresh_token"
        case token
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.tokens) {
            let tokenContainer = try container.nestedContainer(keyedBy: TokenCodingKeys.self, forKey: .tokens)
            accessToken =
                try tokenContainer.decodeIfPresent(String.self, forKey: .accessToken) ??
                tokenContainer.decodeIfPresent(String.self, forKey: .accessTokenSnake) ??
                tokenContainer.decode(String.self, forKey: .token)
            refreshToken =
                try tokenContainer.decodeIfPresent(String.self, forKey: .refreshToken) ??
                tokenContainer.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
        } else {
            accessToken =
                try container.decodeIfPresent(String.self, forKey: .accessToken) ??
                container.decodeIfPresent(String.self, forKey: .accessTokenSnake) ??
                container.decode(String.self, forKey: .token)
            refreshToken =
                try container.decodeIfPresent(String.self, forKey: .refreshToken) ??
                container.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
        }

        user =
            try container.decodeIfPresent(UserDTO.self, forKey: .user) ??
            container.decodeIfPresent(UserDTO.self, forKey: .profile)
    }
}

struct TokenPairResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case accessTokenSnake = "access_token"
        case refreshToken
        case refreshTokenSnake = "refresh_token"
        case token
        case tokens
    }

    private enum TokenCodingKeys: String, CodingKey {
        case accessToken
        case accessTokenSnake = "access_token"
        case refreshToken
        case refreshTokenSnake = "refresh_token"
        case token
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.tokens) {
            let tokenContainer = try container.nestedContainer(keyedBy: TokenCodingKeys.self, forKey: .tokens)
            accessToken =
                try tokenContainer.decodeIfPresent(String.self, forKey: .accessToken) ??
                tokenContainer.decodeIfPresent(String.self, forKey: .accessTokenSnake) ??
                tokenContainer.decode(String.self, forKey: .token)
            refreshToken =
                try tokenContainer.decodeIfPresent(String.self, forKey: .refreshToken) ??
                tokenContainer.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
        } else {
            accessToken =
                try container.decodeIfPresent(String.self, forKey: .accessToken) ??
                container.decodeIfPresent(String.self, forKey: .accessTokenSnake) ??
                container.decode(String.self, forKey: .token)
            refreshToken =
                try container.decodeIfPresent(String.self, forKey: .refreshToken) ??
                container.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
        }
    }
}

struct UserDTO: Decodable, Identifiable {
    let id: String
    let email: String?
    let displayName: String?
    let avatarURL: String?
    let role: String?
    let status: String?
    let referralCode: String?
    let subscriptionTier: String?
    let createdAt: String?
    let defaultGymId: String?
    let onboardingCompletedAt: Date?
    let permissionsState: PermissionsState?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case plainID = "id"
        case email, displayName, avatarURL, role
        case avatarUrl
        case photoUrl
        case roles
        case referralCode, subscriptionTier, createdAt
        case defaultGymId
        case onboardingCompletedAt
        case permissionsState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        id =
            try UserDTO.decodeString(
                from: container,
                candidates: ["_id", "id", "Id"],
                required: true
            ) ?? ""
        email = try UserDTO.decodeString(from: container, candidates: ["email"])
        displayName = try UserDTO.decodeString(from: container, candidates: ["displayName", "display_name"])
        avatarURL = try UserDTO.decodeString(
            from: container,
            candidates: ["avatarURL", "avatarUrl", "avatar_url", "photoUrl", "photo_url"]
        )
        role =
            try UserDTO.decodeString(from: container, candidates: ["role"]) ??
            UserDTO.decodeStringArray(from: container, candidates: ["roles"])?.first
        status = try UserDTO.decodeString(from: container, candidates: ["status"])
        referralCode = try UserDTO.decodeString(from: container, candidates: ["referralCode", "referral_code"])
        subscriptionTier = try UserDTO.decodeString(from: container, candidates: ["subscriptionTier", "subscription_tier"])
        createdAt = try UserDTO.decodeString(from: container, candidates: ["createdAt", "created_at"])
        defaultGymId = try UserDTO.decodeString(from: container, candidates: ["defaultGymId", "default_gym_id"])
        onboardingCompletedAt = try UserDTO.decodeDate(
            from: container,
            candidates: ["onboardingCompletedAt", "onboarding_completed_at"]
        )
        permissionsState = try UserDTO.decodeValue(
            PermissionsState.self,
            from: container,
            candidates: ["permissionsState", "permissions_state"]
        )
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension UserDTO {
    static func decodeString(
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        candidates: [String],
        required: Bool = false
    ) throws -> String? {
        for candidate in candidates {
            guard let key = container.allKeys.first(where: { $0.stringValue == candidate }) else {
                continue
            }

            do {
                if let value = try container.decodeIfPresent(String.self, forKey: key) {
                    return value
                }
            } catch {
                if required {
                    throw error
                }
            }
        }

        if required {
            throw DecodingError.keyNotFound(
                DynamicCodingKey(stringValue: candidates.first ?? "unknown")!,
                .init(codingPath: container.codingPath, debugDescription: "Missing required string field")
            )
        }

        return nil
    }

    static func decodeStringArray(
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        candidates: [String]
    ) -> [String]? {
        for candidate in candidates {
            guard let key = container.allKeys.first(where: { $0.stringValue == candidate }) else {
                continue
            }

            if let value = try? container.decodeIfPresent([String].self, forKey: key) {
                return value
            }
        }

        return nil
    }

    static func decodeDate(
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        candidates: [String]
    ) throws -> Date? {
        for candidate in candidates {
            guard let key = container.allKeys.first(where: { $0.stringValue == candidate }) else {
                continue
            }

            do {
                if let value = try container.decodeIfPresent(Date.self, forKey: key) {
                    return value
                }
            } catch {
                continue
            }
        }

        return nil
    }

    static func decodeValue<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        candidates: [String]
    ) throws -> T? {
        for candidate in candidates {
            guard let key = container.allKeys.first(where: { $0.stringValue == candidate }) else {
                continue
            }

            do {
                if let value = try container.decodeIfPresent(T.self, forKey: key) {
                    return value
                }
            } catch {
                continue
            }
        }

        return nil
    }
}

// MARK: - Response Decoder

/// Decodes API responses, extracting data from the standard envelope or
/// throwing typed `NetworkError` on failure.
struct ResponseDecoder {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
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
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw NetworkError.decodingFailed(context: error.localizedDescription)
            }
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
