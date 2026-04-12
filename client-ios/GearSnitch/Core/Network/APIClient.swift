import Foundation
import os

// MARK: - API Client

/// Actor-based HTTP client wrapping `URLSession` with automatic auth token
/// injection and 401 refresh-retry logic.
actor APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let logger = Logger(subsystem: "com.gearsnitch", category: "APIClient")

    /// Flag to prevent concurrent token refresh attempts.
    private var isRefreshingToken = false
    /// Continuations waiting on an in-flight refresh.
    private var refreshWaiters: [CheckedContinuation<String, Error>] = []

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Execute a typed request, decoding the response from the standard `ApiResponse<T>` envelope.
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = try await executeWithAuth(endpoint)
        do {
            return try ResponseDecoder.decode(T.self, from: data.0, statusCode: data.1)
        } catch {
            logDecodeFailureIfNeeded(for: endpoint, data: data.0, statusCode: data.1, error: error)
            throw error
        }
    }

    /// Execute a request and return raw `Data` (for binary downloads, images, etc.).
    func requestRaw(_ endpoint: APIEndpoint) async throws -> Data {
        let result = try await executeWithAuth(endpoint)
        guard (200...299).contains(result.1) else {
            if result.1 == 401 { throw NetworkError.unauthorized }
            throw NetworkError.serverError(code: result.1, message: "HTTP \(result.1)")
        }
        return result.0
    }

    // MARK: - Internal Execution

    /// Execute with auth, intercepting 401 for one refresh-retry cycle.
    private func executeWithAuth(_ endpoint: APIEndpoint) async throws -> (Data, Int) {
        let tokenStore = TokenStore.shared
        let accessToken = tokenStore.accessToken

        do {
            return try await execute(endpoint, accessToken: accessToken)
        } catch NetworkError.unauthorized {
            logger.info("Received 401, attempting token refresh")
            // Attempt refresh, then retry once
            do {
                let newToken = try await refreshTokenIfNeeded()
                return try await execute(endpoint, accessToken: newToken)
            } catch {
                logger.error("Token refresh failed: \(error.localizedDescription)")
                postSessionExpired()
                throw NetworkError.tokenRefreshFailed
            }
        }
    }

    /// Low-level execution: build request, fire URLSession, check status.
    private func execute(_ endpoint: APIEndpoint, accessToken: String?) async throws -> (Data, Int) {
        guard let baseURL = URL(string: AppConfig.apiBaseURL) else {
            throw NetworkError.invalidURL
        }

        let urlRequest = try RequestBuilder.build(
            from: endpoint,
            baseURL: baseURL,
            accessToken: accessToken,
            refreshToken: TokenStore.shared.refreshToken
        )

        let requestID = urlRequest.value(forHTTPHeaderField: "X-Request-ID") ?? "unknown"

        logger.debug("[\(requestID, privacy: .public)] \(endpoint.method.rawValue) \(urlRequest.url?.absoluteString ?? "?")")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            logger.error("[\(requestID, privacy: .public)] Network request failed for \(endpoint.path, privacy: .public): \(urlError.localizedDescription, privacy: .public)")
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw NetworkError.networkUnavailable
            default:
                throw NetworkError.unknown(statusCode: nil)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(statusCode: nil)
        }

        let statusCode = httpResponse.statusCode

        if statusCode >= 400 {
            logger.error(
                "[\(requestID, privacy: .public)] HTTP \(statusCode) for \(endpoint.path, privacy: .public)"
            )
        } else {
            logger.debug(
                "[\(requestID, privacy: .public)] HTTP \(statusCode) for \(endpoint.path, privacy: .public)"
            )
        }

        if statusCode == 401 {
            throw NetworkError.unauthorized
        }

        return (data, statusCode)
    }

    // MARK: - Token Refresh

    /// Coalesces concurrent refresh requests — only one HTTP call is made,
    /// all waiters receive the same result.
    private func refreshTokenIfNeeded() async throws -> String {
        if isRefreshingToken {
            // Wait for the in-flight refresh
            return try await withCheckedThrowingContinuation { continuation in
                refreshWaiters.append(continuation)
            }
        }

        isRefreshingToken = true

        do {
            let (data, statusCode) = try await execute(
                APIEndpoint.Auth.refresh,
                accessToken: nil
            )

            guard (200...299).contains(statusCode) else {
                throw NetworkError.tokenRefreshFailed
            }

            let tokenResponse = try ResponseDecoder.decode(
                TokenPairResponse.self,
                from: data,
                statusCode: statusCode
            )

            TokenStore.shared.save(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken
            )

            let newToken = tokenResponse.accessToken

            // Resume all waiters
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            isRefreshingToken = false

            for waiter in waiters {
                waiter.resume(returning: newToken)
            }

            return newToken
        } catch {
            // Fail all waiters
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            isRefreshingToken = false

            for waiter in waiters {
                waiter.resume(throwing: error)
            }

            throw error
        }
    }

    // MARK: - Session Expiry

    private func postSessionExpired() {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: AuthManager.sessionExpiredNotification,
                object: nil
            )
        }
    }

    private func logDecodeFailureIfNeeded(
        for endpoint: APIEndpoint,
        data: Data,
        statusCode: Int,
        error: Error
    ) {
        guard endpoint.path.hasPrefix("/api/v1/auth/") else {
            return
        }

        logger.error("Auth decode failure for \(endpoint.path, privacy: .public) (status: \(statusCode), error: \(error.localizedDescription, privacy: .public))")
        logger.error("\(self.sanitizedAuthResponseSummary(from: data), privacy: .public)")
    }

    private func sanitizedAuthResponseSummary(from data: Data) -> String {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let root = jsonObject as? [String: Any]
        else {
            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                return "Auth response body (raw): \(String(raw.prefix(300)))"
            }
            return "Auth response body was empty or non-JSON"
        }

        let topLevelKeys = root.keys.sorted().joined(separator: ",")
        let successDescription = String(describing: root["success"] ?? "nil")

        if let dataObject = root["data"] as? [String: Any] {
            let dataKeys = dataObject.keys.sorted().joined(separator: ",")
            let hasUser = dataObject["user"] != nil
            let hasProfile = dataObject["profile"] != nil
            let hasAccessToken = dataObject["accessToken"] != nil || dataObject["access_token"] != nil
            let hasRefreshToken = dataObject["refreshToken"] != nil || dataObject["refresh_token"] != nil
            let nestedTokenKeys = ((dataObject["tokens"] as? [String: Any])?.keys.sorted().joined(separator: ",")) ?? "none"

            let embeddedUserKeys: String
            if let userObject = dataObject["user"] as? [String: Any] {
                embeddedUserKeys = userObject.keys.sorted().joined(separator: ",")
            } else if let profileObject = dataObject["profile"] as? [String: Any] {
                embeddedUserKeys = profileObject.keys.sorted().joined(separator: ",")
            } else {
                embeddedUserKeys = "none"
            }

            return
                "Auth response summary: topLevelKeys=[\(topLevelKeys)] " +
                "success=\(successDescription) " +
                "dataKeys=[\(dataKeys)] " +
                "hasUser=\(hasUser) hasProfile=\(hasProfile) " +
                "hasAccessToken=\(hasAccessToken) hasRefreshToken=\(hasRefreshToken) " +
                "nestedTokenKeys=[\(nestedTokenKeys)] " +
                "embeddedUserKeys=[\(embeddedUserKeys)]"
        }

        if let errorObject = root["error"] as? [String: Any] {
            let errorKeys = errorObject.keys.sorted().joined(separator: ",")
            return
                "Auth response summary: topLevelKeys=[\(topLevelKeys)] " +
                "success=\(successDescription) errorKeys=[\(errorKeys)]"
        }

        return
            "Auth response summary: topLevelKeys=[\(topLevelKeys)] " +
            "success=\(successDescription) dataType=\(String(describing: type(of: root["data"] as Any)))"
    }
}

// AppConfig is defined in Shared/Models/AppConfig.swift
