import Foundation
import SwiftData

/// The current shape of TriLoop's store: V4 plus workout provenance and
/// athlete-owned templates.
///
/// Two additions — `PlannedWorkout.origin` and `StoredWorkoutTemplate` — one a
/// property with a default, the other a new model, so the stage is lightweight
/// and no existing row is rewritten.
///
/// Introducing V6 means first freezing today's `@Model` declarations the way
/// `TriLoopSchemaV4` freezes yesterday's. Prefer extending a stored `Codable`
/// value — `AthleteSetup`, `TrainingParameters`, `WorkoutStructure` — over
/// adding a property here; those grow without moving the version at all.
enum TriLoopSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            AthleteProfile.self,
            WeeklyPlan.self,
            PlannedWorkout.self,
            WorkoutStep.self,
            WorkoutFeedback.self,
            ImportedWorkoutSummary.self,
            RecoveryCheckIn.self,
            StoredWorkoutTemplate.self
        ]
    }
}
