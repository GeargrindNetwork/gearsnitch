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
        return try ResponseDecoder.decode(T.self, from: data.0, statusCode: data.1)
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
        let baseURL = AppConfig.apiBaseURL

        let urlRequest = try RequestBuilder.build(
            from: endpoint,
            baseURL: baseURL,
            accessToken: accessToken,
            refreshToken: TokenStore.shared.refreshToken
        )

        logger.debug("\(endpoint.method.rawValue) \(urlRequest.url?.absoluteString ?? "?")")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
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
                AuthTokenResponse.self,
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
}

// MARK: - App Config

/// Centralized app configuration.
enum AppConfig {

    /// Base URL for the API server, read from Info.plist or defaulting to staging.
    static var apiBaseURL: URL {
        if let urlString = Bundle.main.infoDictionary?["API_BASE_URL"] as? String,
           let url = URL(string: urlString) {
            return url
        }
        // Default — override in scheme or Info.plist
        return URL(string: "https://api.gearsnitch.com")!
    }
}
