import Foundation
import SwiftData

enum TriLoopSchema {
    /// Always the newest version, so callers never have to track which is current.
    static var models: [any PersistentModel.Type] { TriLoopSchemaV5.models }

    static var current: Schema { Schema(versionedSchema: TriLoopSchemaV5.self) }
}

enum StoreOutcome: Equatable, Sendable {
    case opened
    /// The existing store could not be migrated and was discarded.
    case rebuilt
    /// Nothing could be written to disk. Data will not survive a relaunch.
    case inMemory
}

enum TriLoopModelContainer {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = TriLoopSchema.current
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: schema,
            migrationPlan: TriLoopMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Opens the store, migrating it where possible.
    ///
    /// The rebuild is a last resort for a store the migration plan cannot
    /// handle, not the normal path: subjective feedback cannot be recovered from
    /// HealthKit, so losing it is a real cost.
    static func makeWithFallback() -> (container: ModelContainer, outcome: StoreOutcome) {
        do {
            return (try make(), .opened)
        } catch {
            removeStoreFiles()

            if let rebuilt = try? make() {
                return (rebuilt, .rebuilt)
            }
            guard let memory = try? make(inMemory: true) else {
                fatalError("Unable to create an in-memory SwiftData container")
            }
            return (memory, .inMemory)
        }
    }

    private static func removeStoreFiles() {
        let url = ModelConfiguration(schema: TriLoopSchema.current).url
        let manager = FileManager.default

        // SQLite keeps its write-ahead log and shared memory alongside the store;
        // leaving either behind makes the fresh store fail to open too.
        for path in [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")] {
            try? manager.removeItem(at: path)
        }
    }
}
