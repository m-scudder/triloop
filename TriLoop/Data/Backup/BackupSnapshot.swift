import Foundation
import SwiftData

/// Versioned, backend-neutral representation of everything TriLoop owns.
///
/// This is intentionally not a database schema. A Supabase adapter can map
/// these records to relational tables while restore remains independent of the
/// remote provider.
struct BackupSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let createdAt: Date
    let profile: AthleteProfileBackup?
    let plans: [WeeklyPlanBackup]
    let templates: [StoredWorkoutTemplateBackup]

    init(
        schemaVersion: Int = currentSchemaVersion,
        createdAt: Date = .now,
        profile: AthleteProfileBackup?,
        plans: [WeeklyPlanBackup],
        templates: [StoredWorkoutTemplateBackup]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.profile = profile
        self.plans = plans
        self.templates = templates
    }

    @MainActor
    static func capture(from context: ModelContext, at date: Date = .now) throws -> BackupSnapshot {
        let profiles = try context.fetch(FetchDescriptor<AthleteProfile>())
        let plans = try context.fetch(
            FetchDescriptor<WeeklyPlan>(sortBy: [SortDescriptor(\.startDate)])
        )
        let templates = try context.fetch(
            FetchDescriptor<StoredWorkoutTemplate>(sortBy: [SortDescriptor(\.updatedAt)])
        )

        return BackupSnapshot(
            createdAt: date,
            profile: profiles.first.map(AthleteProfileBackup.init),
            plans: plans.map(WeeklyPlanBackup.init),
            templates: templates.map(StoredWorkoutTemplateBackup.init)
        )
    }
}

struct AthleteProfileBackup: Codable, Sendable {
    let id: UUID
    let name: String
    let experienceLevel: ExperienceLevel
    let trainingStartDate: Date
    let poolLengthMeters: Double
    let usesMetricUnits: Bool
    let setup: AthleteSetup?

    @MainActor
    init(_ profile: AthleteProfile) {
        id = profile.id
        name = profile.name
        experienceLevel = profile.experienceLevel
        trainingStartDate = profile.trainingStartDate
        poolLengthMeters = profile.poolLengthMeters
        usesMetricUnits = profile.usesMetricUnits
        setup = profile.setup
    }

    @MainActor
    func restore() -> AthleteProfile {
        AthleteProfile(
            id: id,
            name: name,
            experienceLevel: experienceLevel,
            trainingStartDate: trainingStartDate,
            poolLengthMeters: poolLengthMeters,
            usesMetricUnits: usesMetricUnits,
            setup: setup
        )
    }
}

struct WeeklyPlanBackup: Codable, Sendable {
    let id: UUID
    let weekNumber: Int
    let startDate: Date
    let endDate: Date
    let status: WeeklyPlanStatus
    let generatedAt: Date
    let generationReason: String
    let generationReasonCode: PlanGenerationReason?
    let parameters: TrainingParameters
    let workouts: [PlannedWorkoutBackup]

    @MainActor
    init(_ plan: WeeklyPlan) {
        id = plan.id
        weekNumber = plan.weekNumber
        startDate = plan.startDate
        endDate = plan.endDate
        status = plan.status
        generatedAt = plan.generatedAt
        generationReason = plan.generationReason
        generationReasonCode = plan.generationReasonCode
        parameters = plan.parameters
        workouts = plan.orderedWorkouts.map(PlannedWorkoutBackup.init)
    }

    @MainActor
    func restore() -> WeeklyPlan {
        WeeklyPlan(
            id: id,
            weekNumber: weekNumber,
            startDate: startDate,
            endDate: endDate,
            status: status,
            generatedAt: generatedAt,
            generationReason: generationReason,
            generationReasonCode: generationReasonCode,
            parameters: parameters,
            workouts: workouts.map { $0.restore() }
        )
    }
}

struct PlannedWorkoutBackup: Codable, Sendable {
    let id: UUID
    let date: Date
    let discipline: Discipline
    let title: String
    let goal: String
    let targetRPE: RPERange?
    let prescribedDurationSeconds: TimeInterval?
    let targetDistanceMeters: Double?
    let status: PlannedWorkoutStatus
    let completedAt: Date?
    let origin: WorkoutOrigin
    let steps: [WorkoutStepBackup]
    let feedback: WorkoutFeedbackBackup?
    let importedSummary: ImportedWorkoutBackup?
    let recoveryCheckIn: RecoveryCheckInBackup?

    @MainActor
    init(_ workout: PlannedWorkout) {
        id = workout.id
        date = workout.date
        discipline = workout.discipline
        title = workout.title
        goal = workout.goal
        targetRPE = workout.targetRPE
        prescribedDurationSeconds = workout.prescribedDurationSeconds
        targetDistanceMeters = workout.targetDistanceMeters
        status = workout.status
        completedAt = workout.completedAt
        origin = workout.origin
        steps = workout.orderedSteps.map(WorkoutStepBackup.init)
        feedback = workout.feedback.map(WorkoutFeedbackBackup.init)
        importedSummary = workout.importedSummary.map(ImportedWorkoutBackup.init)
        recoveryCheckIn = workout.recoveryCheckIn.map(RecoveryCheckInBackup.init)
    }

    @MainActor
    func restore() -> PlannedWorkout {
        let workout = PlannedWorkout(
            id: id,
            date: date,
            discipline: discipline,
            title: title,
            goal: goal,
            targetRPE: targetRPE,
            prescribedDurationSeconds: prescribedDurationSeconds,
            targetDistanceMeters: targetDistanceMeters,
            status: status,
            origin: origin,
            steps: steps.map { $0.restore() }
        )
        workout.completedAt = completedAt
        workout.feedback = feedback?.restore()
        workout.importedSummary = importedSummary?.restore()
        workout.recoveryCheckIn = recoveryCheckIn?.restore()
        return workout
    }
}

struct WorkoutStepBackup: Codable, Sendable {
    let id: UUID
    let order: Int
    let kind: WorkoutStepKind
    let title: String
    let instructions: String?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let targetIntensity: TargetIntensity?
    let repeatCount: Int?
    let children: [WorkoutStepBackup]

    @MainActor
    init(_ step: WorkoutStep) {
        id = step.id
        order = step.order
        kind = step.kind
        title = step.title
        instructions = step.instructions
        durationSeconds = step.durationSeconds
        distanceMeters = step.distanceMeters
        targetIntensity = step.targetIntensity
        repeatCount = step.repeatCount
        children = step.orderedChildren.map(WorkoutStepBackup.init)
    }

    @MainActor
    func restore() -> WorkoutStep {
        WorkoutStep(
            id: id,
            order: order,
            kind: kind,
            title: title,
            instructions: instructions,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            targetIntensity: targetIntensity,
            repeatCount: repeatCount,
            children: children.map { $0.restore() }
        )
    }
}

struct WorkoutFeedbackBackup: Codable, Sendable {
    let id: UUID
    let rpe: Int
    let painScore: Int
    let painLocations: [PainLocation]
    let recoveryFeeling: RecoveryFeeling
    let symptoms: [WarningSymptom]
    let notes: String
    let createdAt: Date

    @MainActor
    init(_ feedback: WorkoutFeedback) {
        id = feedback.id
        rpe = feedback.rpe
        painScore = feedback.painScore
        painLocations = feedback.painLocations
        recoveryFeeling = feedback.recoveryFeeling
        symptoms = feedback.symptoms
        notes = feedback.notes
        createdAt = feedback.createdAt
    }

    @MainActor
    func restore() -> WorkoutFeedback {
        WorkoutFeedback(
            id: id,
            rpe: rpe,
            painScore: painScore,
            painLocations: painLocations,
            recoveryFeeling: recoveryFeeling,
            symptoms: symptoms,
            notes: notes,
            createdAt: createdAt
        )
    }
}

struct RecoveryCheckInBackup: Codable, Sendable {
    let id: UUID
    let date: Date
    let painScore: Int
    let soreness: SorenessLevel
    let energy: EnergyLevel
    let symptoms: [WarningSymptom]
    let createdAt: Date

    @MainActor
    init(_ checkIn: RecoveryCheckIn) {
        id = checkIn.id
        date = checkIn.date
        painScore = checkIn.painScore
        soreness = checkIn.soreness
        energy = checkIn.energy
        symptoms = checkIn.symptoms
        createdAt = checkIn.createdAt
    }

    @MainActor
    func restore() -> RecoveryCheckIn {
        RecoveryCheckIn(
            id: id,
            date: date,
            painScore: painScore,
            soreness: soreness,
            energy: energy,
            symptoms: symptoms,
            createdAt: createdAt
        )
    }
}

struct ImportedWorkoutBackup: Codable, Sendable {
    let id: UUID
    let healthKitUUID: UUID
    let sport: Sport
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMeters: Double?
    let averageHeartRate: Double?
    let maximumHeartRate: Double?
    let elevationAscendedMeters: Double?
    let swimmingLengths: Int?
    let swimmingStrokeCount: Double?
    let longestContinuousSwimMeters: Double?
    let metrics: RecordedMetrics?
    let source: String?
    let importedAt: Date

    @MainActor
    init(_ summary: ImportedWorkoutSummary) {
        id = summary.id
        healthKitUUID = summary.healthKitUUID
        sport = summary.sport
        startDate = summary.startDate
        endDate = summary.endDate
        duration = summary.duration
        distanceMeters = summary.distanceMeters
        averageHeartRate = summary.averageHeartRate
        maximumHeartRate = summary.maximumHeartRate
        elevationAscendedMeters = summary.elevationAscendedMeters
        swimmingLengths = summary.swimmingLengths
        swimmingStrokeCount = summary.swimmingStrokeCount
        longestContinuousSwimMeters = summary.longestContinuousSwimMeters
        metrics = summary.metrics
        source = summary.source
        importedAt = summary.importedAt
    }

    @MainActor
    func restore() -> ImportedWorkoutSummary {
        ImportedWorkoutSummary(
            id: id,
            healthKitUUID: healthKitUUID,
            sport: sport,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            elevationAscendedMeters: elevationAscendedMeters,
            swimmingLengths: swimmingLengths,
            swimmingStrokeCount: swimmingStrokeCount,
            longestContinuousSwimMeters: longestContinuousSwimMeters,
            metrics: metrics,
            source: source,
            importedAt: importedAt
        )
    }
}

struct StoredWorkoutTemplateBackup: Codable, Sendable {
    let id: UUID
    let sport: Sport
    let name: String
    let category: WorkoutCategory
    let purpose: String
    let structure: WorkoutStructure
    let targetRPE: RPERange?
    let createdAt: Date
    let updatedAt: Date

    @MainActor
    init(_ template: StoredWorkoutTemplate) {
        id = template.id
        sport = template.sport
        name = template.name
        category = template.category
        purpose = template.purpose
        structure = template.structure
        targetRPE = template.targetRPE
        createdAt = template.createdAt
        updatedAt = template.updatedAt
    }

    @MainActor
    func restore() -> StoredWorkoutTemplate {
        StoredWorkoutTemplate(
            id: id,
            sport: sport,
            name: name,
            category: category,
            purpose: purpose,
            structure: structure,
            targetRPE: targetRPE,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
