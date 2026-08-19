import Foundation

/// Sensor-derived values from a completed workout that the plan does not need
/// to reason about structurally.
///
/// Stored as a single `Codable` attribute rather than one column per metric, the
/// same way `TrainingParameters` is. Adding a field here changes no `@Model`
/// shape, so the schema version does not move and no migration stage is needed —
/// which matters because the interesting metrics differ by sport and by watch,
/// and the list will keep growing.
///
/// Every field is optional: HealthKit records what the device happened to
/// capture, and absence is normal rather than an error.
struct RecordedMetrics: Codable, Equatable, Sendable {
    /// Steps per minute. A proxy for running cadence, taken from `stepCount`.
    var averageCadence: Double?

    // Running. Speed is on any watch; the rest need newer hardware.
    var averageRunningSpeed: Double?
    var averageRunningPower: Double?
    var averageStrideLength: Double?
    var averageGroundContactTime: Double?
    var averageVerticalOscillation: Double?

    // Cycling. Power and FTP need a meter, which most riders do not own.
    var averageCyclingSpeed: Double?
    var averageCyclingCadence: Double?
    var averageCyclingPower: Double?
    var functionalThresholdPower: Double?

    /// Apple's effort score, rated by the athlete in the Workout app.
    ///
    /// Kept apart from TriLoop's RPE on purpose: they are different questions,
    /// asked at different moments, and §27 requires them not to be conflated.
    var workoutEffort: Double?
    /// Apple's own estimate, when the athlete rated nothing.
    var estimatedWorkoutEffort: Double?

    init(
        averageCadence: Double? = nil,
        averageRunningSpeed: Double? = nil,
        averageRunningPower: Double? = nil,
        averageStrideLength: Double? = nil,
        averageGroundContactTime: Double? = nil,
        averageVerticalOscillation: Double? = nil,
        averageCyclingSpeed: Double? = nil,
        averageCyclingCadence: Double? = nil,
        averageCyclingPower: Double? = nil,
        functionalThresholdPower: Double? = nil,
        workoutEffort: Double? = nil,
        estimatedWorkoutEffort: Double? = nil
    ) {
        self.averageCadence = averageCadence
        self.averageRunningSpeed = averageRunningSpeed
        self.averageRunningPower = averageRunningPower
        self.averageStrideLength = averageStrideLength
        self.averageGroundContactTime = averageGroundContactTime
        self.averageVerticalOscillation = averageVerticalOscillation
        self.averageCyclingSpeed = averageCyclingSpeed
        self.averageCyclingCadence = averageCyclingCadence
        self.averageCyclingPower = averageCyclingPower
        self.functionalThresholdPower = functionalThresholdPower
        self.workoutEffort = workoutEffort
        self.estimatedWorkoutEffort = estimatedWorkoutEffort
    }

    /// Decoded key by key so a record written by an older build, which had fewer
    /// fields, still loads. The synthesized decoder would throw on the missing
    /// keys and take the whole workout summary with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil
        }

        averageCadence = value(.averageCadence)
        averageRunningSpeed = value(.averageRunningSpeed)
        averageRunningPower = value(.averageRunningPower)
        averageStrideLength = value(.averageStrideLength)
        averageGroundContactTime = value(.averageGroundContactTime)
        averageVerticalOscillation = value(.averageVerticalOscillation)
        averageCyclingSpeed = value(.averageCyclingSpeed)
        averageCyclingCadence = value(.averageCyclingCadence)
        averageCyclingPower = value(.averageCyclingPower)
        functionalThresholdPower = value(.functionalThresholdPower)
        workoutEffort = value(.workoutEffort)
        estimatedWorkoutEffort = value(.estimatedWorkoutEffort)
    }

    var isEmpty: Bool {
        [
            averageCadence,
            averageRunningSpeed,
            averageRunningPower,
            averageStrideLength,
            averageGroundContactTime,
            averageVerticalOscillation,
            averageCyclingSpeed,
            averageCyclingCadence,
            averageCyclingPower,
            functionalThresholdPower,
            workoutEffort,
            estimatedWorkoutEffort
        ].allSatisfy { $0 == nil }
    }

    /// The effort Apple holds, preferring what the athlete rated over what the
    /// system guessed.
    var appleEffort: Double? { workoutEffort ?? estimatedWorkoutEffort }
}
