import Foundation
import SwiftData
import os

// MARK: - Local Store

/// SwiftData `ModelContainer` setup and shared instance for local persistence.
@MainActor
final class LocalStore {

    static let shared = LocalStore()

    let container: ModelContainer

    private let logger = Logger(subsystem: "com.gearsnitch", category: "LocalStore")

    private init() {
        let schema = Schema([
            LocalDevice.self,
            LocalDeviceEvent.self,
            LocalGym.self,
            OfflineOperation.self,
            DoseHistoryEntry.self,
        ])

        let modelConfiguration = ModelConfiguration(
            "GearSnitch",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            logger.info("SwiftData container initialized")
        } catch {
            // Fatal: if we can't create the container, the app cannot function.
            fatalError("Failed to create SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }

    /// The main model context for UI operations.
    var mainContext: ModelContext {
        container.mainContext
    }

    /// Create a new background context for non-UI work.
    func newBackgroundContext() -> ModelContext {
        ModelContext(container)
    }
}
