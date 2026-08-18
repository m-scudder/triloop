import Foundation
import SwiftData

/// The store as it was before athlete personalisation.
///
/// These are frozen copies, deliberately duplicated rather than referencing the
/// live models: SwiftData checksums a version from its model *definitions*, so
/// two versions sharing types collide with "Duplicate version checksums
/// detected". Nesting them keeps the old shape addressable without colliding
/// with the current declarations.
///
/// Never edit these to match a change elsewhere. A frozen version describes a
/// store that already exists on someone's device; changing it makes the
/// migration lie.
enum TriLoopSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

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

    @Model
    final class AthleteProfile {
        var id: UUID = UUID()
        var name: String = ""
        var experienceLevel: ExperienceLevel = ExperienceLevel.beginner
        var trainingStartDate: Date = Date.now
        var poolLengthMeters: Double = 25
        var usesMetricUnits: Bool = true

        init() {}
    }

    @Model
    final class WeeklyPlan {
        var id: UUID = UUID()
        var weekNumber: Int = 1
        var startDate: Date = Date.now
        var endDate: Date = Date.now
        var status: WeeklyPlanStatus = WeeklyPlanStatus.active
        var generatedAt: Date = Date.now
        var generationReason: String = ""
        var parameters: TrainingParameters = TrainingParameters()

        @Relationship(deleteRule: .cascade, inverse: \PlannedWorkout.plan)
        var workouts: [PlannedWorkout] = []

        init() {}
    }

    @Model
    final class PlannedWorkout {
        var id: UUID = UUID()
        var date: Date = Date.now
        var discipline: Discipline = Discipline.rest
        var title: String = ""
        var goal: String = ""
        var targetRPE: RPERange?
        var prescribedDurationSeconds: TimeInterval?
        var targetDistanceMeters: Double?
        var status: PlannedWorkoutStatus = PlannedWorkoutStatus.planned
        var completedAt: Date?

        var plan: WeeklyPlan?

        @Relationship(deleteRule: .cascade, inverse: \WorkoutStep.workout)
        var steps: [WorkoutStep] = []

        @Relationship(deleteRule: .cascade, inverse: \WorkoutFeedback.workout)
        var feedback: WorkoutFeedback?

        @Relationship(deleteRule: .cascade, inverse: \ImportedWorkoutSummary.workout)
        var importedSummary: ImportedWorkoutSummary?

        @Relationship(deleteRule: .cascade, inverse: \RecoveryCheckIn.workout)
        var recoveryCheckIn: RecoveryCheckIn?

        init() {}
    }

    @Model
    final class WorkoutStep {
        var id: UUID = UUID()
        var order: Int = 0
        var kind: WorkoutStepKind = WorkoutStepKind.work
        var title: String = ""
        var instructions: String?
        var durationSeconds: TimeInterval?
        var distanceMeters: Double?
        var targetIntensity: TargetIntensity?
        var repeatCount: Int?

        var workout: PlannedWorkout?
        var parent: WorkoutStep?

        @Relationship(deleteRule: .cascade, inverse: \WorkoutStep.parent)
        var children: [WorkoutStep] = []

        init() {}
    }

    @Model
    final class WorkoutFeedback {
        var id: UUID = UUID()
        var rpe: Int = 0
        var painScore: Int = 0
        var painLocations: [PainLocation] = []
        var recoveryFeeling: RecoveryFeeling = RecoveryFeeling.okay
        var symptoms: [WarningSymptom] = []
        var notes: String = ""
        var createdAt: Date = Date.now

        var workout: PlannedWorkout?

        init() {}
    }

    @Model
    final class ImportedWorkoutSummary {
        var id: UUID = UUID()
        @Attribute(.unique) var healthKitUUID: UUID = UUID()
        var sport: Sport = Sport.running
        var startDate: Date = Date.now
        var endDate: Date = Date.now
        var duration: TimeInterval = 0
        var distanceMeters: Double?
        var averageHeartRate: Double?
        var maximumHeartRate: Double?
        var elevationAscendedMeters: Double?
        var swimmingLengths: Int?
        var swimmingStrokeCount: Double?
        var longestContinuousSwimMeters: Double?
        var metrics: RecordedMetrics?
        var source: String?
        var importedAt: Date = Date.now

        var workout: PlannedWorkout?

        init() {}
    }

    @Model
    final class RecoveryCheckIn {
        var id: UUID = UUID()
        var date: Date = Date.now
        var painScore: Int = 0
        var soreness: SorenessLevel = SorenessLevel.none
        var energy: EnergyLevel = EnergyLevel.normal
        var symptoms: [WarningSymptom] = []
        var createdAt: Date = Date.now

        var workout: PlannedWorkout?

        init() {}
    }
}
