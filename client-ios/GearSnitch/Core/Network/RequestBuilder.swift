import Foundation

/// Builds a `URLRequest` from an `APIEndpoint`, injecting auth tokens and
/// standard headers.
struct RequestBuilder {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()

    /// Build a fully configured `URLRequest` for the given endpoint.
    ///
    /// - Parameters:
    ///   - endpoint: The API endpoint definition.
    ///   - baseURL: The base URL for the API server.
    ///   - accessToken: Optional Bearer token for authenticated requests.
    ///   - refreshToken: Optional refresh token injected as a cookie/body for refresh endpoints.
    /// - Returns: A configured `URLRequest`.
    static func build(
        from endpoint: APIEndpoint,
        baseURL: URL,
        accessToken: String? = nil,
        refreshToken: String? = nil
    ) throws -> URLRequest {
        // Construct URL
        guard var components = buildURLComponents(baseURL: baseURL, endpoint: endpoint) else {
            throw NetworkError.invalidURL
        }

        if let queryItems = endpoint.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = 30

        // Standard headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GearSnitch-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")

        // Auth header
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Refresh token — sent in body for refresh endpoint
        if endpoint.path.hasSuffix("/auth/refresh"), let rt = refreshToken {
            let refreshBody = RefreshTokenRequestBody(refreshToken: rt)
            request.httpBody = try encoder.encode(refreshBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // Regular body
        else if let body = endpoint.body {
            request.httpBody = try encodeBody(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    // MARK: - Private

    private static func buildURLComponents(baseURL: URL, endpoint: APIEndpoint) -> URLComponents? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            return nil
        }

        let baseSegments = components.path
            .split(separator: "/")
            .map(String.init)
        let endpointSegments = endpoint.path
            .split(separator: "/")
            .map(String.init)

        let mergedSegments: [String]
        if endpointSegments.starts(with: baseSegments) {
            mergedSegments = endpointSegments
        } else {
            mergedSegments = baseSegments + endpointSegments
        }

        components.path = mergedSegments.isEmpty ? "/" : "/" + mergedSegments.joined(separator: "/")
        return components
    }

    private static func encodeBody(_ body: any Encodable) throws -> Data {
        do {
            return try encoder.encode(AnyEncodable(body))
        } catch {
            throw NetworkError.decodingFailed(context: "Failed to encode request body: \(error.localizedDescription)")
        }
    }
}

// MARK: - Refresh Token Body

private struct RefreshTokenRequestBody: Encodable {
    let refreshToken: String
}

// MARK: - Type-erased Encodable wrapper

/// Wraps any `Encodable` value so it can be encoded without generic constraints
/// at the call site.
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
