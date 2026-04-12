import Foundation
import os

// MARK: - Socket Client

/// Actor wrapping `URLSessionWebSocketTask` for real-time communication.
/// Connects with JWT auth, supports exponential backoff reconnection
/// (1s -> 2s -> 4s -> 8s, max 60s), and refreshes JWT before reconnect.
actor SocketClient {

    static var shared: SocketClient { SocketClient() }

    // MARK: - State

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    private(set) var state: ConnectionState = .disconnected

    // MARK: - Configuration

    private static let initialBackoff: TimeInterval = 1
    private static let maxBackoff: TimeInterval = 60
    private static let backoffMultiplier: Double = 2

    // MARK: - Private Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private let logger = Logger(subsystem: "com.gearsnitch", category: "SocketClient")

    private var currentBackoff: TimeInterval = 1.0
    private var shouldReconnect = false
    private var receiveTask: Task<Void, Never>?

    /// Handler for incoming messages. Set by `SocketEventHandler`.
    var onMessage: ((URLSessionWebSocketTask.Message) -> Void)?

    /// Handler for connection state changes.
    var onStateChange: ((ConnectionState) -> Void)?

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Connect

    /// Connect to the WebSocket server with the current JWT.
    func connect() async {
        guard state == .disconnected || state == .reconnecting else {
            logger.debug("Already connected or connecting")
            return
        }

        shouldReconnect = true
        await performConnect()
    }

    /// Disconnect from the WebSocket server.
    func disconnect() {
        shouldReconnect = false
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        currentBackoff = Self.initialBackoff
        updateState(.disconnected)
        logger.info("WebSocket disconnected")
    }

    // MARK: - Send

    /// Send a text message over the WebSocket.
    func send(_ text: String) async throws {
        guard let task = webSocketTask, state == .connected else {
            throw SocketError.notConnected
        }
        try await task.send(.string(text))
    }

    /// Send a JSON-encodable message over the WebSocket.
    func send<T: Encodable>(event: String, payload: T) async throws {
        let envelope = SocketEnvelope(event: event, data: payload)
        let data = try JSONEncoder().encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SocketError.encodingFailed
        }
        try await send(text)
    }

    // MARK: - Private: Connection

    private func performConnect() async {
        updateState(.connecting)

        // Get a fresh access token
        let token: String
        do {
            let tokenStore = TokenStore.shared
            if tokenStore.isAccessTokenExpired {
                token = try await AuthManager.shared.refreshToken()
            } else {
                token = tokenStore.accessToken ?? ""
            }
        } catch {
            logger.error("Failed to get token for WebSocket: \(error.localizedDescription)")
            await scheduleReconnect()
            return
        }

        guard let wsURL = Self.buildWebSocketURL(token: token) else {
            logger.error("Invalid WebSocket URL")
            await scheduleReconnect()
            return
        }

        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("GearSnitch-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        updateState(.connected)
        currentBackoff = Self.initialBackoff
        logger.info("WebSocket connected")

        // Start receive loop
        startReceiving()
    }

    static func buildWebSocketURL(baseURL: String = AppConfig.socketURL, token: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else {
            return nil
        }

        let pathSegments = components.path
            .split(separator: "/")
            .map(String.init)
        let normalizedPathSegments = pathSegments.last == "ws" ? pathSegments : pathSegments + ["ws"]

        components.path = normalizedPathSegments.isEmpty
            ? "/ws"
            : "/" + normalizedPathSegments.joined(separator: "/")

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "token" }
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems

        return components.url
    }

    // MARK: - Private: Receive Loop

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let task = await self.webSocketTask else { break }

                do {
                    let message = try await task.receive()
                    await self.handleMessage(message)
                } catch {
                    if !Task.isCancelled {
                        await self.handleDisconnect(error: error)
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        onMessage?(message)
    }

    private func handleDisconnect(error: Error) async {
        logger.warning("WebSocket disconnected: \(error.localizedDescription)")
        webSocketTask = nil
        updateState(.disconnected)

        if shouldReconnect {
            await scheduleReconnect()
        }
    }

    // MARK: - Private: Reconnection

    private func scheduleReconnect() async {
        guard shouldReconnect else { return }

        updateState(.reconnecting)
        let delay = currentBackoff
        currentBackoff = min(currentBackoff * Self.backoffMultiplier, Self.maxBackoff)

        logger.info("Reconnecting in \(delay)s (next backoff: \(self.currentBackoff)s)")

        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            return // Task cancelled
        }

        guard shouldReconnect else { return }

        // Refresh JWT before reconnect
        do {
            _ = try await AuthManager.shared.refreshToken()
        } catch {
            logger.warning("Token refresh before reconnect failed: \(error.localizedDescription)")
        }

        await performConnect()
    }

    // MARK: - Private: State

    private func updateState(_ newState: ConnectionState) {
        state = newState
        onStateChange?(newState)
    }
}

// MARK: - Socket Error

enum SocketError: LocalizedError {
    case notConnected
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WebSocket is not connected."
        case .encodingFailed:
            return "Failed to encode WebSocket message."
        }
    }
}

// MARK: - Socket Envelope

struct SocketEnvelope<T: Encodable>: Encodable {
    let event: String
    let data: T
}
