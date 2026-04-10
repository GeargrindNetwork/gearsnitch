import Foundation
import Network
import SwiftData
import os

// MARK: - Offline Queue

/// Monitors network connectivity and replays queued offline operations
/// when the network becomes available. Uses `NWPathMonitor` for reachability
/// and exponential backoff with a max of 3 retries per operation.
@MainActor
final class OfflineQueue: ObservableObject {

    static let shared = OfflineQueue()

    // MARK: - Constants

    private static let maxRetries = 3
    private static let initialBackoff: TimeInterval = 1
    private static let backoffMultiplier: Double = 2

    // MARK: - Published State

    @Published private(set) var isOnline = true
    @Published private(set) var pendingCount = 0

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.gearsnitch.network-monitor")
    private let logger = Logger(subsystem: "com.gearsnitch", category: "OfflineQueue")
    private var isProcessing = false

    private init() {}

    // MARK: - Start Monitoring

    /// Start monitoring network connectivity. Call once at app launch.
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied

                if wasOffline && self.isOnline {
                    self.logger.info("Network restored — processing offline queue")
                    await self.processQueue()
                } else if !self.isOnline {
                    self.logger.info("Network lost")
                }
            }
        }

        monitor.start(queue: monitorQueue)
        logger.info("Network monitoring started")
    }

    /// Stop monitoring network connectivity.
    func stopMonitoring() {
        monitor.cancel()
    }

    // MARK: - Enqueue

    /// Enqueue an operation to be retried when the network is available.
    func enqueue(endpoint: String, method: String, body: Data?) {
        let context = LocalStore.shared.mainContext
        let operation = OfflineOperation(
            endpoint: endpoint,
            method: method,
            body: body
        )

        context.insert(operation)

        do {
            try context.save()
            updatePendingCount()
            logger.info("Enqueued offline operation: \(method) \(endpoint)")
        } catch {
            logger.error("Failed to enqueue offline operation: \(error.localizedDescription)")
        }

        // If online, process immediately
        if isOnline {
            Task {
                await processQueue()
            }
        }
    }

    // MARK: - Process Queue

    /// Process all pending offline operations in creation order.
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer {
            isProcessing = false
            updatePendingCount()
        }

        let context = LocalStore.shared.newBackgroundContext()

        let descriptor = FetchDescriptor<OfflineOperation>(
            predicate: #Predicate { !$0.isPermanentlyFailed },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        guard let operations = try? context.fetch(descriptor), !operations.isEmpty else {
            logger.debug("No pending offline operations")
            return
        }

        logger.info("Processing \(operations.count) offline operations")

        for operation in operations {
            guard isOnline else {
                logger.info("Network lost during queue processing — stopping")
                break
            }

            let success = await executeOperation(operation)

            if success {
                context.delete(operation)
                logger.debug("Completed offline operation: \(operation.method) \(operation.endpoint)")
            } else if operation.retryCount >= Self.maxRetries {
                operation.isPermanentlyFailed = true
                logger.warning("Permanently failed operation: \(operation.method) \(operation.endpoint) after \(Self.maxRetries) retries")
            } else {
                operation.retryCount += 1
                operation.lastAttemptAt = Date()
                logger.debug("Retry \(operation.retryCount)/\(Self.maxRetries) for: \(operation.method) \(operation.endpoint)")

                // Exponential backoff between retries
                let delay = Self.initialBackoff * pow(Self.backoffMultiplier, Double(operation.retryCount - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            try? context.save()
        }

        await MainActor.run {
            self.updatePendingCount()
        }
    }

    // MARK: - Execute

    private func executeOperation(_ operation: OfflineOperation) async -> Bool {
        let endpoint = APIEndpoint(
            path: operation.endpoint,
            method: HTTPMethod(rawValue: operation.method) ?? .POST,
            body: operation.body.map { RawBody(data: $0) }
        )

        do {
            let _: EmptyData = try await APIClient.shared.request(endpoint)
            return true
        } catch {
            logger.error("Offline operation failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Count

    private func updatePendingCount() {
        let context = LocalStore.shared.mainContext
        let descriptor = FetchDescriptor<OfflineOperation>(
            predicate: #Predicate { !$0.isPermanentlyFailed }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Cleanup

    /// Remove all permanently failed operations.
    func clearFailedOperations() {
        let context = LocalStore.shared.mainContext
        let descriptor = FetchDescriptor<OfflineOperation>(
            predicate: #Predicate { $0.isPermanentlyFailed }
        )

        if let failed = try? context.fetch(descriptor) {
            for op in failed {
                context.delete(op)
            }
            try? context.save()
            updatePendingCount()
        }
    }
}

// MARK: - Raw Body

/// Wrapper to pass pre-encoded Data through the Encodable pipeline.
private struct RawBody: Encodable {
    let data: Data

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Encode as base64 string; the RequestBuilder will handle it
        try container.encode(data.base64EncodedString())
    }
}
