import Foundation
import os

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let senderId: String
    let senderName: String
    let text: String
    let timestamp: Date
    let isOutgoing: Bool

    init(
        id: String = UUID().uuidString,
        senderId: String,
        senderName: String,
        text: String,
        timestamp: Date = Date(),
        isOutgoing: Bool
    ) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
    }
}

// MARK: - MeshChat ViewModel

@MainActor
final class MeshChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var nearbyUsers: Int = 0
    @Published var anonymousId: String
    @Published var anonymousName: String
    @Published var messageText: String = ""
    @Published var gymName: String = "Nearby"
    @Published var isConnected: Bool = false

    private let meshManager: MeshNetworkManager
    private let logger = Logger(subsystem: "com.gearsnitch", category: "MeshChat")

    private static let keychainAnonymousIdKey = "com.gearsnitch.meshchat.anonymousId"
    private static let keychainAnonymousNameKey = "com.gearsnitch.meshchat.anonymousName"

    // MARK: - Init

    init() {
        // Load or generate anonymous identity from Keychain
        if let storedId = KeychainStore.shared.loadString(forKey: Self.keychainAnonymousIdKey),
           let storedName = KeychainStore.shared.loadString(forKey: Self.keychainAnonymousNameKey) {
            self.anonymousId = storedId
            self.anonymousName = storedName
        } else {
            let newId = UUID().uuidString
            let randomNumber = Int.random(in: 1...99)
            let prefixes = ["Lifter", "Athlete", "Trainer", "Beast", "Grinder", "Warrior"]
            let prefix = prefixes.randomElement() ?? "User"
            let newName = "\(prefix) #\(randomNumber)"

            self.anonymousId = newId
            self.anonymousName = newName

            try? KeychainStore.shared.save(newId, forKey: Self.keychainAnonymousIdKey)
            try? KeychainStore.shared.save(newName, forKey: Self.keychainAnonymousNameKey)
        }

        self.meshManager = MeshNetworkManager.shared

        // Bind mesh manager callbacks
        setupCallbacks()
    }

    // MARK: - Lifecycle

    func startChat() {
        meshManager.start(peerId: anonymousId, displayName: anonymousName)
        isConnected = true
        logger.info("Mesh chat started as \(self.anonymousName)")
    }

    func stopChat() {
        meshManager.stop()
        isConnected = false
        logger.info("Mesh chat stopped")
    }

    // MARK: - Send Message

    func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = ChatMessage(
            senderId: anonymousId,
            senderName: anonymousName,
            text: trimmed,
            isOutgoing: true
        )

        messages.append(message)
        messageText = ""

        meshManager.send(message: message)
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        meshManager.onMessageReceived = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Mark as incoming
                let incoming = ChatMessage(
                    id: message.id,
                    senderId: message.senderId,
                    senderName: message.senderName,
                    text: message.text,
                    timestamp: message.timestamp,
                    isOutgoing: false
                )
                // Deduplicate by id
                if !self.messages.contains(where: { $0.id == incoming.id }) {
                    self.messages.append(incoming)
                }
            }
        }

        meshManager.onPeerCountChanged = { [weak self] count in
            Task { @MainActor [weak self] in
                self?.nearbyUsers = count
            }
        }

        meshManager.onPeerJoined = { [weak self] peerName in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let systemMessage = ChatMessage(
                    senderId: "system",
                    senderName: "System",
                    text: "\(peerName) joined the mesh",
                    isOutgoing: false
                )
                self.messages.append(systemMessage)
            }
        }

        meshManager.onPeerLeft = { [weak self] peerName in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let systemMessage = ChatMessage(
                    senderId: "system",
                    senderName: "System",
                    text: "\(peerName) left the mesh",
                    isOutgoing: false
                )
                self.messages.append(systemMessage)
            }
        }
    }
}
