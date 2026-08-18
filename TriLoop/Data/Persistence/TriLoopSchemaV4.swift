import Foundation
import SwiftData

/// The current shape of TriLoop's store: V3 plus athlete personalisation.
///
/// Two properties were added — `AthleteProfile.setup` and
/// `WeeklyPlan.generationReasonCode` — both optional and both `Codable`, so the
/// stage below is lightweight and no existing row needs rewriting.
///
/// Introducing V5 means first freezing today's `@Model` declarations the way
/// `TriLoopSchemaV3` freezes yesterday's. Prefer extending a stored `Codable`
/// value — `AthleteSetup`, `TrainingParameters`, `RecordedMetrics` — over adding
/// a property here; those grow without moving the version at all.
enum TriLoopSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

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
        [TriLoopSchemaV3.self, TriLoopSchemaV4.self]
    }

    /// Adding optional properties needs no data transformation, so the stage is
    /// lightweight. It still has to exist: without it, a V3 store cannot be
    /// opened at all and the fallback would discard the athlete's history.
    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(
                fromVersion: TriLoopSchemaV3.self,
                toVersion: TriLoopSchemaV4.self
            )
        ]
    }
}
