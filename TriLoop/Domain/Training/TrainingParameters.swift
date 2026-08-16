import Foundation

/// The dials a week's workouts are built from.
///
/// Progression works by changing these and rebuilding the week, rather than
/// mutating an existing step tree. That keeps generation deterministic and makes
/// "what changed since last week" a diff of two small value types.
///
/// The defaults are week one exactly as seeded.
struct TrainingParameters: Codable, Equatable, Sendable {
    var runWarmUpSeconds: TimeInterval = 5 * 60
    var runIntervalSeconds: TimeInterval = 60
    var runWalkSeconds: TimeInterval = 120
    var runRepeatCount: Int = 6
    var runCooldownSeconds: TimeInterval = 5 * 60

    var swimRepeatDistanceMeters: Double = 25
    var swimTotalMeters: Double = 300
    var swimRestSeconds: TimeInterval = 45

    var rideWarmUpSeconds: TimeInterval = 5 * 60
    var rideWorkSeconds: TimeInterval = 20 * 60
    var rideCooldownSeconds: TimeInterval = 5 * 60

    init() {}
}

extension TrainingParameters {
    /// Floors that stop repeated reductions from producing a workout too small
    /// to be worth doing.
    enum Limits {
        static let minimumRunIntervalSeconds: TimeInterval = 30
        static let minimumRunRepeatCount = 3
        static let minimumSwimRestSeconds: TimeInterval = 20
        static let minimumSwimMeters: Double = 100
        static let minimumRideWorkSeconds: TimeInterval = 10 * 60
    }

    func applying(_ adjustment: TrainingAdjustment, to sport: Sport) -> TrainingParameters {
        var next = self

        switch adjustment {
        case .hold, .substituteRecovery:
            break

        case .runIntervalDuration(let delta):
            next.runIntervalSeconds = max(
                runIntervalSeconds + delta,
                Limits.minimumRunIntervalSeconds
            )

        case .rideDuration(let delta):
            next.rideWorkSeconds = max(
                rideWorkSeconds + delta,
                Limits.minimumRideWorkSeconds
            )

        case .swimRestDuration(let delta):
            next.swimRestSeconds = max(
                swimRestSeconds + delta,
                Limits.minimumSwimRestSeconds
            )

        case .swimVolume(let delta):
            next.swimTotalMeters = Self.roundedToRepeat(
                max(swimTotalMeters + delta, Limits.minimumSwimMeters),
                repeatDistance: swimRepeatDistanceMeters
            )

        case .reduceVolume(let fraction):
            next.reduceVolume(by: fraction, for: sport)
        }

        return next
    }

    /// Volume is reduced with each sport's own primary variable: repeats for
    /// running, distance for swimming, duration for cycling.
    private mutating func reduceVolume(by fraction: Double, for sport: Sport) {
        let remaining = 1 - min(max(fraction, 0), 1)

        switch sport {
        case .running:
            runRepeatCount = max(
                Int((Double(runRepeatCount) * remaining).rounded()),
                Limits.minimumRunRepeatCount
            )
        case .swimming:
            swimTotalMeters = Self.roundedToRepeat(
                max(swimTotalMeters * remaining, Limits.minimumSwimMeters),
                repeatDistance: swimRepeatDistanceMeters
            )
        case .cycling:
            rideWorkSeconds = max(
                (rideWorkSeconds * remaining).rounded(),
                Limits.minimumRideWorkSeconds
            )
        }
    }

    /// Swim volume only means something in whole lengths of the pool.
    private static func roundedToRepeat(_ meters: Double, repeatDistance: Double) -> Double {
        guard repeatDistance > 0 else { return meters }
        return (meters / repeatDistance).rounded() * repeatDistance
    }
}
