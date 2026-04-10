import Foundation
import os

// MARK: - Socket Event

/// Raw decoded event from a WebSocket message.
struct SocketEvent: Decodable {
    let event: String
    let data: AnyCodable
}

// MARK: - Socket Event Handler

/// Routes incoming WebSocket messages to typed handlers by event name.
/// Decodes the raw message, extracts the event name, and dispatches to
/// the appropriate handler closure.
final class SocketEventHandler {

    private let logger = Logger(subsystem: "com.gearsnitch", category: "SocketEventHandler")

    /// Registered event handlers keyed by event name.
    private var handlers: [String: (Data) -> Void] = [:]

    /// Catch-all handler for unrecognized events.
    var onUnhandledEvent: ((String, Data) -> Void)?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Registration

    /// Register a typed handler for a specific event name.
    func on<T: Decodable>(_ eventName: String, type: T.Type, handler: @escaping (T) -> Void) {
        handlers[eventName] = { [weak self] data in
            guard let self else { return }
            do {
                let decoded = try self.decoder.decode(T.self, from: data)
                handler(decoded)
            } catch {
                self.logger.error("Failed to decode event '\(eventName)': \(error.localizedDescription)")
            }
        }
    }

    /// Register a handler for an event with no payload data.
    func on(_ eventName: String, handler: @escaping () -> Void) {
        handlers[eventName] = { _ in
            handler()
        }
    }

    /// Remove a handler for an event name.
    func off(_ eventName: String) {
        handlers.removeValue(forKey: eventName)
    }

    /// Remove all handlers.
    func removeAllHandlers() {
        handlers.removeAll()
    }

    // MARK: - Message Processing

    /// Process a raw WebSocket message. Extracts the event name and routes
    /// to the registered handler.
    func processMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data

        switch message {
        case .string(let text):
            guard let textData = text.data(using: .utf8) else {
                logger.warning("Failed to convert WebSocket text to data")
                return
            }
            data = textData

        case .data(let binaryData):
            data = binaryData

        @unknown default:
            logger.warning("Unknown WebSocket message type")
            return
        }

        // Extract event name
        guard let event = try? decoder.decode(SocketEvent.self, from: data) else {
            logger.warning("Failed to decode WebSocket event envelope")
            return
        }

        let eventName = event.event

        if let handler = handlers[eventName] {
            handler(data)
        } else {
            logger.debug("Unhandled WebSocket event: \(eventName)")
            onUnhandledEvent?(eventName, data)
        }
    }
}

// MARK: - AnyCodable

/// A type-erased Codable wrapper for heterogeneous JSON data.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable cannot decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable cannot encode \(type(of: value))"
                )
            )
        }
    }
}
