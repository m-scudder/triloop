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
    /// Once the walk breaks are no longer needed, running becomes one block.
    var runIsContinuous: Bool = false
    var runContinuousSeconds: TimeInterval = 0

    var swimRepeatDistanceMeters: Double = 25
    var swimTotalMeters: Double = 300
    var swimRestSeconds: TimeInterval = 45
    /// The pool the week was built for. A dial rather than a profile lookup, so
    /// a plan stays reproducible even if the athlete later changes pools.
    var swimPoolLengthMeters: Double = 25

    var rideWarmUpSeconds: TimeInterval = 5 * 60
    var rideWorkSeconds: TimeInterval = 20 * 60
    var rideCooldownSeconds: TimeInterval = 5 * 60

    init() {}

    /// Decoded key by key so parameters stored by an older build, which had
    /// fewer fields, still load. The synthesized decoder would throw on the
    /// missing keys and take the whole plan with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TrainingParameters()

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }

        runWarmUpSeconds = value(.runWarmUpSeconds, defaults.runWarmUpSeconds)
        runIntervalSeconds = value(.runIntervalSeconds, defaults.runIntervalSeconds)
        runWalkSeconds = value(.runWalkSeconds, defaults.runWalkSeconds)
        runRepeatCount = value(.runRepeatCount, defaults.runRepeatCount)
        runCooldownSeconds = value(.runCooldownSeconds, defaults.runCooldownSeconds)
        runIsContinuous = value(.runIsContinuous, defaults.runIsContinuous)
        runContinuousSeconds = value(.runContinuousSeconds, defaults.runContinuousSeconds)
        swimRepeatDistanceMeters = value(.swimRepeatDistanceMeters, defaults.swimRepeatDistanceMeters)
        swimTotalMeters = value(.swimTotalMeters, defaults.swimTotalMeters)
        swimRestSeconds = value(.swimRestSeconds, defaults.swimRestSeconds)
        swimPoolLengthMeters = value(.swimPoolLengthMeters, defaults.swimPoolLengthMeters)
        rideWarmUpSeconds = value(.rideWarmUpSeconds, defaults.rideWarmUpSeconds)
        rideWorkSeconds = value(.rideWorkSeconds, defaults.rideWorkSeconds)
        rideCooldownSeconds = value(.rideCooldownSeconds, defaults.rideCooldownSeconds)
    }
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
        static let minimumRunWalkSeconds: TimeInterval = 30
        static let minimumContinuousRunSeconds: TimeInterval = 8 * 60

        /// Rest cannot be tightened indefinitely, and a longer repeat needs more
        /// of it: 30 seconds after 25 m is brisk, after 100 m it is nothing.
        static func restFloor(forRepeat meters: Double) -> TimeInterval {
            let scaled = (30 * (meters / 25)).rounded()
            return max(min(scaled, 90), minimumSwimRestSeconds)
        }

        /// Rest allowed above the floor when a repeat lengthens, so tightening
        /// it is available as the next week's lever.
        static let restHeadroomSeconds: TimeInterval = 15
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

        case .runWalkDuration(let delta):
            next.runWalkSeconds = max(
                runWalkSeconds + delta,
                Limits.minimumRunWalkSeconds
            )

        case .graduateToContinuousRun:
            next.runIsContinuous = true
            // Half the interval work, not all of it: running without breaks is
            // harder than the same minutes broken up.
            next.runContinuousSeconds = max(
                (runIntervalSeconds * Double(runRepeatCount) / 2).rounded(),
                Limits.minimumContinuousRunSeconds
            )

        case .runContinuousDuration(let delta):
            next.runContinuousSeconds = max(
                runContinuousSeconds + delta,
                Limits.minimumContinuousRunSeconds
            )

        case .rideDuration(let delta):
            next.rideWorkSeconds = max(
                rideWorkSeconds + delta,
                Limits.minimumRideWorkSeconds
            )

        case .swimRestDuration(let delta):
            next.swimRestSeconds = max(
                swimRestSeconds + delta,
                Limits.restFloor(forRepeat: swimRepeatDistanceMeters)
            )

        case .swimRepeatDistance(let meters):
            next.swimRepeatDistanceMeters = meters
            // Landing exactly on the new floor would leave the rest lever with
            // no room, so distance would step again the very next week. One
            // decrement of headroom makes the two levers alternate.
            next.swimRestSeconds = Limits.restFloor(forRepeat: meters) + Limits.restHeadroomSeconds
            next.swimTotalMeters = Self.roundedToRepeat(
                swimTotalMeters,
                repeatDistance: meters
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
            if runIsContinuous {
                runContinuousSeconds = max(
                    (runContinuousSeconds * remaining).rounded(),
                    Limits.minimumContinuousRunSeconds
                )
            } else {
                runRepeatCount = max(
                    Int((Double(runRepeatCount) * remaining).rounded()),
                    Limits.minimumRunRepeatCount
                )
            }
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
