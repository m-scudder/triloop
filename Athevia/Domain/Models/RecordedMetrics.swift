import Foundation

/// A compact GPS point recorded by Athevia's iPhone workout player.
///
/// Route data lives inside `RecordedMetrics`, so adding phone GPS does not move
/// the SwiftData schema. Timestamp is retained so later analysis can derive
/// segment pace without inventing samples that were never recorded.
struct RecordedRoutePoint: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double?
    var timestamp: Date
}

/// Sensor-derived values from a completed workout that the plan does not need
/// to reason about structurally.
///
/// Stored as a single `Codable` attribute rather than one column per metric, the
/// same way `TrainingParameters` is. Adding a field here changes no `@Model`
/// shape, so the schema version does not move and no migration stage is needed —
/// which matters because the interesting metrics differ by sport and by watch,
/// and the list will keep growing.
enum RecordedSwimEnvironment: String, Codable, Equatable, Sendable {
    case pool
    case openWater
}

struct RecordedMultisportSegment: Codable, Equatable, Sendable {
    var sport: Sport?
    var isTransition: Bool
    var durationSeconds: TimeInterval
    var distanceMeters: Double?
    var swimEnvironment: RecordedSwimEnvironment?

    init(
        sport: Sport?,
        isTransition: Bool = false,
        durationSeconds: TimeInterval,
        distanceMeters: Double? = nil,
        swimEnvironment: RecordedSwimEnvironment? = nil
    ) {
        self.sport = sport
        self.isTransition = isTransition
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.swimEnvironment = swimEnvironment
    }
}

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
    /// Kept apart from Athevia's RPE on purpose: they are different questions.
    var workoutEffort: Double?
    /// Apple's own estimate, when the athlete rated nothing.
    var estimatedWorkoutEffort: Double?

    /// Multisport activities are kept as explicit per-sport evidence. A
    /// transition has nil sport and isTransition=true.
    var multisportSegments: [RecordedMultisportSegment]
    var swimEnvironment: RecordedSwimEnvironment?

    /// GPS points captured by Athevia itself. HealthKit imports normally leave
    /// this empty because their sample stream remains in HealthKit.
    var route: [RecordedRoutePoint]

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
        estimatedWorkoutEffort: Double? = nil,
        multisportSegments: [RecordedMultisportSegment] = [],
        swimEnvironment: RecordedSwimEnvironment? = nil,
        route: [RecordedRoutePoint] = []
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
        self.multisportSegments = multisportSegments
        self.swimEnvironment = swimEnvironment
        self.route = route
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
        multisportSegments = value(.multisportSegments) ?? []
        swimEnvironment = value(.swimEnvironment)
        route = value(.route) ?? []
    }

    var isEmpty: Bool {
        let scalarMetrics = [
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
        ]
        return scalarMetrics.allSatisfy { $0 == nil }
            && multisportSegments.isEmpty
            && swimEnvironment == nil
            && route.isEmpty
    }

    /// The effort Apple holds, preferring what the athlete rated over what the
    /// system guessed.
    var appleEffort: Double? { workoutEffort ?? estimatedWorkoutEffort }
}