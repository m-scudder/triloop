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
    /// Bundle identifier of the app that recorded it, e.g. Apple's Workout app.
    let source: String?

    var id: UUID { healthKitUUID }

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
