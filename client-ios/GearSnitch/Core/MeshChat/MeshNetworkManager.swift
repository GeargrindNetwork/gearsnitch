import Foundation
import MultipeerConnectivity
import os

// MARK: - Mesh Network Manager

/// MultipeerConnectivity-based mesh networking for anonymous local chat.
/// Uses Bonjour/WiFi + BLE for peer discovery within ~50m range.
final class MeshNetworkManager: NSObject {

    static let shared = MeshNetworkManager()

    // MARK: - Constants

    /// Service type must be 1-15 characters, lowercase ASCII + hyphens.
    private static let serviceType = "gsnitch-chat"

    // MARK: - Callbacks

    var onMessageReceived: ((ChatMessage) -> Void)?
    var onPeerCountChanged: ((Int) -> Void)?
    var onPeerJoined: ((String) -> Void)?
    var onPeerLeft: ((String) -> Void)?

    // MARK: - Private State

    private var peerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// Maps peer IDs to their anonymous display names.
    private var peerDisplayNames: [MCPeerID: String] = [:]

    /// Our own display name for sending in invitation context.
    private var ownDisplayName: String?

    private let logger = Logger(subsystem: "com.gearsnitch", category: "MeshNetwork")

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var isRunning = false

    // MARK: - Init

    private override init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        super.init()
    }

    // MARK: - Start / Stop

    /// Start advertising and browsing for nearby peers.
    /// - Parameters:
    ///   - peerId: Unique anonymous identifier for this user.
    ///   - displayName: Anonymous display name (e.g., "Lifter #42").
    func start(peerId: String, displayName: String) {
        guard !isRunning else { return }

        // Use a truncated hash of the peerId for MCPeerID to avoid
        // exposing the real device name.
        let anonymizedName = String(peerId.prefix(15))
        let mcPeerID = MCPeerID(displayName: anonymizedName)
        self.peerID = mcPeerID

        let session = MCSession(
            peer: mcPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
        self.session = session

        // Advertiser — includes display name in discovery info
        let advertiser = MCNearbyServiceAdvertiser(
            peer: mcPeerID,
            discoveryInfo: ["name": displayName],
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        // Browser
        let browser = MCNearbyServiceBrowser(
            peer: mcPeerID,
            serviceType: Self.serviceType
        )
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        isRunning = true
        logger.info("Mesh network started (displayName: \(displayName))")
    }

    func stop() {
        guard isRunning else { return }

        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()

        advertiser = nil
        browser = nil
        session = nil
        peerID = nil
        peerDisplayNames.removeAll()
        isRunning = false

        logger.info("Mesh network stopped")
    }

    // MARK: - Send

    func send(message: ChatMessage) {
        guard let session, !session.connectedPeers.isEmpty else {
            logger.debug("No connected peers to send message to")
            return
        }

        do {
            let data = try encoder.encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            logger.debug("Sent message to \(session.connectedPeers.count) peer(s)")
        } catch {
            logger.error("Failed to send message: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func notifyPeerCount() {
        let count = session?.connectedPeers.count ?? 0
        onPeerCountChanged?(count)
    }

    private func displayName(for peer: MCPeerID) -> String {
        peerDisplayNames[peer] ?? "User"
    }
}

// MARK: - MCSessionDelegate

extension MeshNetworkManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = displayName(for: peerID)

        switch state {
        case .connected:
            logger.info("Peer connected: \(name)")
            onPeerJoined?(name)
        case .notConnected:
            logger.info("Peer disconnected: \(name)")
            peerDisplayNames.removeValue(forKey: peerID)
            onPeerLeft?(name)
        case .connecting:
            logger.debug("Peer connecting: \(peerID.displayName)")
        @unknown default:
            break
        }

        notifyPeerCount()
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let message = try decoder.decode(ChatMessage.self, from: data)
            logger.debug("Received message from \(self.displayName(for: peerID))")
            onMessageReceived?(message)
        } catch {
            logger.error("Failed to decode received message: \(error.localizedDescription)")
        }
    }

    // Unused required delegate methods
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MeshNetworkManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // Auto-accept invitations from nearby peers
        logger.info("Received invitation from \(peerID.displayName) — auto-accepting")

        // Extract display name from context if provided
        if let context, let info = try? JSONDecoder().decode([String: String].self, from: context) {
            if let name = info["name"] {
                peerDisplayNames[peerID] = name
            }
        }

        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        logger.error("Failed to start advertising: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MeshNetworkManager: MCNearbyServiceBrowserDelegate {

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        logger.info("Found peer: \(peerID.displayName)")

        // Store peer's anonymous display name from discovery info
        if let name = info?["name"] {
            peerDisplayNames[peerID] = name
        }

        // Invite the peer — pass our display name in context
        guard let session else { return }

        var contextData: Data?
        if let selfName = advertiser?.discoveryInfo?["name"] {
            contextData = try? JSONEncoder().encode(["name": selfName])
        }

        browser.invitePeer(
            peerID,
            to: session,
            withContext: contextData,
            timeout: 30
        )
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.info("Lost peer: \(peerID.displayName)")
        // MCSession delegate handles the actual disconnection
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        logger.error("Failed to start browsing: \(error.localizedDescription)")
    }
}
