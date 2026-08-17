import Foundation
import SwiftData

/// The current shape of TriLoop's store.
///
/// A second version cannot simply reference these same types: SwiftData
/// checksums each version from its model definitions, and two versions
/// describing the same shape collide with "Duplicate version checksums".
/// Introducing V3 means first copying today's `@Model` declarations into a
/// frozen `TriLoopSchemaV2` namespace, then adding a stage between them.
enum TriLoopSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            AthleteProfile.self,
            WeeklyPlan.self,
            PlannedWorkout.self,
            WorkoutStep.self,
            WorkoutFeedback.self,
            ImportedWorkoutSummary.self,
            RecoveryCheckIn.self
        ]
    }
}

enum TriLoopMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TriLoopSchemaV2.self]
    }

    /// Empty while there is one version. Each version added after this needs a
    /// stage, or stores created by the previous build cannot be opened.
    static var stages: [MigrationStage] { [] }
}
