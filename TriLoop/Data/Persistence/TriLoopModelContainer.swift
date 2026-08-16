import Foundation
import SwiftData

enum TriLoopSchema {
    static let models: [any PersistentModel.Type] = [
        AthleteProfile.self,
        WeeklyPlan.self,
        PlannedWorkout.self,
        WorkoutStep.self
    ]
}

enum TriLoopModelContainer {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(TriLoopSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Falls back to an in-memory store so a corrupt or unmigratable file never
    /// prevents the app from launching. The caller can surface this to the user.
    static func makeWithFallback() -> (container: ModelContainer, usedFallback: Bool) {
        do {
            return (try make(), false)
        } catch {
            do {
                return (try make(inMemory: true), true)
            } catch {
                fatalError("Unable to create an in-memory SwiftData container: \(error)")
            }
        }
    }
}
