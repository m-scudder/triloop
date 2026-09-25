import Foundation

/// A completed workout, normalized away from HealthKit.
///
/// §10: HealthKit types stay at the boundary. Nothing downstream of the provider
/// knows `HKWorkout` exists, which is what keeps the matcher and the training
/// engine testable without entitlements or a device.
struct ImportedWorkout: Equatable, Sendable, Identifiable {
    /// `HKWorkout.uuid`. The stable identity for de-duplicating repeat imports.
    let healthKitUUID: UUID
    let sport: Sport
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMeters: Double?
    let averageHeartRate: Double?
    let maximumHeartRate: Double?
    let elevationAscendedMeters: Double?
    /// Pool lengths swum, from the workout's lap events.
    let swimmingLengths: Int?
    let swimmingStrokeCount: Double?
    /// Longest distance swum without stopping. §14 progresses on continuous
    /// swimming, which total distance alone cannot show.
    let longestContinuousSwimMeters: Double?
    /// Sensor values that need no schema column of their own.
    var metrics: RecordedMetrics
    /// Exact Athevia plan identity when the workout was recorded by Athevia Watch.
    let plannedWorkoutID: UUID?
    /// Fraction of the concrete structured prescription completed on Athevia Watch.
    let prescriptionCompletion: Double?
    let completedPrescriptionSteps: Int?
    let totalPrescriptionSteps: Int?
    /// Bundle identifier of the app that recorded it, e.g. Apple's Workout app.
    let source: String?

    var id: UUID { healthKitUUID }

    /// Explicit activity semantics for downstream matching and capability.
    /// `sport` remains the legacy single-sport carrier for compatibility.
    var discipline: Discipline {
        metrics.multisportSegments.isEmpty ? sport.discipline : .multisport
    }

    init(
        healthKitUUID: UUID,
        sport: Sport,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil,
        elevationAscendedMeters: Double? = nil,
        swimmingLengths: Int? = nil,
        swimmingStrokeCount: Double? = nil,
        longestContinuousSwimMeters: Double? = nil,
        metrics: RecordedMetrics = RecordedMetrics(),
        plannedWorkoutID: UUID? = nil,
        prescriptionCompletion: Double? = nil,
        completedPrescriptionSteps: Int? = nil,
        totalPrescriptionSteps: Int? = nil,
        source: String? = nil
    ) {
        self.healthKitUUID = healthKitUUID
        self.sport = sport
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.elevationAscendedMeters = elevationAscendedMeters
        self.swimmingLengths = swimmingLengths
        self.swimmingStrokeCount = swimmingStrokeCount
        self.longestContinuousSwimMeters = longestContinuousSwimMeters
        self.metrics = metrics
        self.plannedWorkoutID = plannedWorkoutID
        self.prescriptionCompletion = prescriptionCompletion
        self.completedPrescriptionSteps = completedPrescriptionSteps
        self.totalPrescriptionSteps = totalPrescriptionSteps
        self.source = source
    }
}

extension ImportedWorkout {
    /// Feeds the training engine. Completion is supplied by the caller, which is
    /// the only party that knows what was planned.
    func result(completion: Double, prescribedRestSeconds: TimeInterval? = nil) -> WorkoutResult {
        WorkoutResult(
            sport: sport,
            completion: completion,
            durationSeconds: duration,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            prescribedRestSeconds: prescribedRestSeconds
        )
    }
}
