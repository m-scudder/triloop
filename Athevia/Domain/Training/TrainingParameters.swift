import Foundation

/// The dials a week's workouts are built from.
///
/// New run/cycle prescriptions are distance-first. Legacy time fields remain
/// encoded so plans written by older builds still decode and so capability
/// history can retain its previous reference values.
struct TrainingParameters: Codable, Equatable, Sendable {
    // MARK: Running

    var runWarmUpDistanceMeters: Double = 250
    var runIntervalDistanceMeters: Double = 150
    var runWalkDistanceMeters: Double = 100
    var runRepeatCount: Int = 6
    var runCooldownDistanceMeters: Double = 250
    var runIsContinuous: Bool = false
    var runContinuousDistanceMeters: Double = 1_500

    // Backward-compatible/internal progression proxies.
    var runWarmUpSeconds: TimeInterval = 5 * 60
    var runIntervalSeconds: TimeInterval = 60
    var runWalkSeconds: TimeInterval = 120
    var runCooldownSeconds: TimeInterval = 5 * 60
    var runContinuousSeconds: TimeInterval = 0

    // MARK: Swimming

    var swimRepeatDistanceMeters: Double = 25
    var swimTotalMeters: Double = 300
    var swimRestSeconds: TimeInterval = 45
    var swimPoolLengthMeters: Double = 25

    // MARK: Cycling

    var rideWarmUpDistanceMeters: Double = 500
    var rideWorkDistanceMeters: Double = 3_000
    var rideCooldownDistanceMeters: Double = 500

    // Backward-compatible/internal progression proxies.
    var rideWarmUpSeconds: TimeInterval = 5 * 60
    var rideWorkSeconds: TimeInterval = 20 * 60
    var rideCooldownSeconds: TimeInterval = 5 * 60

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TrainingParameters()

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }

        runWarmUpDistanceMeters = value(.runWarmUpDistanceMeters, defaults.runWarmUpDistanceMeters)
        runIntervalDistanceMeters = value(.runIntervalDistanceMeters, defaults.runIntervalDistanceMeters)
        runWalkDistanceMeters = value(.runWalkDistanceMeters, defaults.runWalkDistanceMeters)
        runRepeatCount = value(.runRepeatCount, defaults.runRepeatCount)
        runCooldownDistanceMeters = value(.runCooldownDistanceMeters, defaults.runCooldownDistanceMeters)
        runIsContinuous = value(.runIsContinuous, defaults.runIsContinuous)
        runContinuousDistanceMeters = value(.runContinuousDistanceMeters, defaults.runContinuousDistanceMeters)

        runWarmUpSeconds = value(.runWarmUpSeconds, defaults.runWarmUpSeconds)
        runIntervalSeconds = value(.runIntervalSeconds, defaults.runIntervalSeconds)
        runWalkSeconds = value(.runWalkSeconds, defaults.runWalkSeconds)
        runCooldownSeconds = value(.runCooldownSeconds, defaults.runCooldownSeconds)
        runContinuousSeconds = value(.runContinuousSeconds, defaults.runContinuousSeconds)

        swimRepeatDistanceMeters = value(.swimRepeatDistanceMeters, defaults.swimRepeatDistanceMeters)
        swimTotalMeters = value(.swimTotalMeters, defaults.swimTotalMeters)
        swimRestSeconds = value(.swimRestSeconds, defaults.swimRestSeconds)
        swimPoolLengthMeters = value(.swimPoolLengthMeters, defaults.swimPoolLengthMeters)

        rideWarmUpDistanceMeters = value(.rideWarmUpDistanceMeters, defaults.rideWarmUpDistanceMeters)
        rideWorkDistanceMeters = value(.rideWorkDistanceMeters, defaults.rideWorkDistanceMeters)
        rideCooldownDistanceMeters = value(.rideCooldownDistanceMeters, defaults.rideCooldownDistanceMeters)

        rideWarmUpSeconds = value(.rideWarmUpSeconds, defaults.rideWarmUpSeconds)
        rideWorkSeconds = value(.rideWorkSeconds, defaults.rideWorkSeconds)
        rideCooldownSeconds = value(.rideCooldownSeconds, defaults.rideCooldownSeconds)
    }
}

extension TrainingParameters {
    enum Limits {
        static let minimumRunIntervalDistanceMeters: Double = 100
        static let minimumRunWalkDistanceMeters: Double = 50
        static let minimumContinuousRunDistanceMeters: Double = 1_000
        static let minimumRunRepeatCount = 3
        static let minimumRideWorkDistanceMeters: Double = 2_000

        // Legacy proxy floors retained for old plans/capability calculations.
        static let minimumRunIntervalSeconds: TimeInterval = 30
        static let minimumRunWalkSeconds: TimeInterval = 30
        static let minimumContinuousRunSeconds: TimeInterval = 8 * 60
        static let minimumRideWorkSeconds: TimeInterval = 10 * 60

        static let minimumSwimRestSeconds: TimeInterval = 20
        static let minimumSwimMeters: Double = 100

        static func restFloor(forRepeat meters: Double) -> TimeInterval {
            let scaled = (30 * (meters / 25)).rounded()
            return max(min(scaled, 90), minimumSwimRestSeconds)
        }

        static let restHeadroomSeconds: TimeInterval = 15
    }

    var runTargetDistanceMeters: Double {
        runWarmUpDistanceMeters
            + runCooldownDistanceMeters
            + (runIsContinuous
                ? runContinuousDistanceMeters
                : Double(runRepeatCount) * (runIntervalDistanceMeters + runWalkDistanceMeters))
    }

    var rideTargetDistanceMeters: Double {
        rideWarmUpDistanceMeters + rideWorkDistanceMeters + rideCooldownDistanceMeters
    }

    /// Secondary time estimate only; prescription/execution remains distance-based.
    var estimatedRunDurationSeconds: TimeInterval {
        // Conservative mixed easy-run / walk estimate.
        (runTargetDistanceMeters / 1_000) * 9 * 60
    }

    /// Secondary time estimate only; prescription/execution remains distance-based.
    var estimatedRideDurationSeconds: TimeInterval {
        // Conservative recreational cycling estimate (~15 km/h).
        (rideTargetDistanceMeters / 1_000) * 4 * 60
    }

    /// Availability is still a ceiling. It may cap a distance prescription,
    /// but never turns it back into a time prescription.
    func capped(toTrainingMinutes minutes: Int?) -> TrainingParameters {
        guard let minutes, minutes > 0 else { return self }
        var next = self

        let cap = TimeInterval(minutes * 60)

        // Keep legacy time proxies capped for capability/history compatibility.
        let runTimeBudget = max(cap - next.runWarmUpSeconds - next.runCooldownSeconds, 0)
        if next.runIsContinuous {
            next.runContinuousSeconds = min(next.runContinuousSeconds, runTimeBudget)
        } else {
            let repeatSeconds = next.runIntervalSeconds + next.runWalkSeconds
            if repeatSeconds > 0 {
                let maxRepeats = Int((runTimeBudget / repeatSeconds).rounded(.down))
                next.runRepeatCount = min(next.runRepeatCount, max(maxRepeats, 1))
            }
        }
        let rideTimeBudget = max(cap - next.rideWarmUpSeconds - next.rideCooldownSeconds, 0)
        next.rideWorkSeconds = min(next.rideWorkSeconds, rideTimeBudget)

        let runCap = Double(minutes) / 60.0 * 6_500
        let fixedRun = next.runWarmUpDistanceMeters + next.runCooldownDistanceMeters
        let runWorkCap = max(runCap - fixedRun, Limits.minimumContinuousRunDistanceMeters)

        if next.runIsContinuous {
            next.runContinuousDistanceMeters = min(next.runContinuousDistanceMeters, runWorkCap)
        } else {
            let currentRepeat = next.runIntervalDistanceMeters + next.runWalkDistanceMeters
            let maxPerRepeat = max(runWorkCap / Double(max(next.runRepeatCount, 1)), 1)
            if currentRepeat > maxPerRepeat {
                let ratio = maxPerRepeat / currentRepeat
                next.runIntervalDistanceMeters = max(
                    Self.rounded(next.runIntervalDistanceMeters * ratio, to: 25),
                    Limits.minimumRunIntervalDistanceMeters
                )
                next.runWalkDistanceMeters = max(
                    Self.rounded(next.runWalkDistanceMeters * ratio, to: 25),
                    Limits.minimumRunWalkDistanceMeters
                )
            }
        }

        let rideCap = Double(minutes) / 60.0 * 15_000
        let fixedRide = next.rideWarmUpDistanceMeters + next.rideCooldownDistanceMeters
        next.rideWorkDistanceMeters = min(
            next.rideWorkDistanceMeters,
            max(rideCap - fixedRide, Limits.minimumRideWorkDistanceMeters)
        )

        return next
    }

    /// Preserve the previous product behavior where a selected training window
    /// is a useful session budget, but convert that budget into conservative
    /// distance rather than prescribing minutes.
    func fillingTrainingWindow(minutes: Int?, bufferMinutes: Int = 5) -> TrainingParameters {
        guard let minutes, minutes > 0 else { return self }
        var next = self
        let targetMinutes = Double(max(minutes - bufferMinutes, 1))
        let targetSeconds = TimeInterval(targetMinutes * 60)

        // Preserve legacy proxy behavior while the emitted prescription remains
        // distance-based.
        let rideWorkBudgetSeconds = max(
            targetSeconds - next.rideWarmUpSeconds - next.rideCooldownSeconds,
            Limits.minimumRideWorkSeconds
        )
        next.rideWorkSeconds = max(next.rideWorkSeconds, rideWorkBudgetSeconds)

        if next.runIsContinuous {
            let runWorkBudgetSeconds = max(
                targetSeconds - next.runWarmUpSeconds - next.runCooldownSeconds,
                Limits.minimumContinuousRunSeconds
            )
            next.runContinuousSeconds = max(next.runContinuousSeconds, runWorkBudgetSeconds)
        } else {
            let runWorkBudgetSeconds = max(
                targetSeconds - next.runWarmUpSeconds - next.runCooldownSeconds,
                0
            )
            let repeatSeconds = next.runIntervalSeconds + next.runWalkSeconds
            if repeatSeconds > 0 {
                let targetRepeats = Int((runWorkBudgetSeconds / repeatSeconds).rounded(.down))
                next.runRepeatCount = max(next.runRepeatCount, max(targetRepeats, 1))
            }
        }

        let runTarget = targetMinutes / 60.0 * 6_500
        let fixedRun = next.runWarmUpDistanceMeters + next.runCooldownDistanceMeters
        let runWorkTarget = max(runTarget - fixedRun, Limits.minimumContinuousRunDistanceMeters)
        if next.runIsContinuous {
            next.runContinuousDistanceMeters = max(next.runContinuousDistanceMeters, Self.rounded(runWorkTarget, to: 250))
        } else {
            let current = next.runIntervalDistanceMeters + next.runWalkDistanceMeters
            let desiredPerRepeat = runWorkTarget / Double(max(next.runRepeatCount, 1))
            if desiredPerRepeat > current {
                let ratio = desiredPerRepeat / current
                next.runIntervalDistanceMeters = Self.rounded(next.runIntervalDistanceMeters * ratio, to: 25)
                next.runWalkDistanceMeters = Self.rounded(next.runWalkDistanceMeters * ratio, to: 25)
            }
        }

        let rideTarget = targetMinutes / 60.0 * 15_000
        let fixedRide = next.rideWarmUpDistanceMeters + next.rideCooldownDistanceMeters
        next.rideWorkDistanceMeters = max(
            next.rideWorkDistanceMeters,
            Self.rounded(max(rideTarget - fixedRide, Limits.minimumRideWorkDistanceMeters), to: 500)
        )

        return next.capped(toTrainingMinutes: minutes)
    }

    func applying(_ adjustment: TrainingAdjustment, to sport: Sport) -> TrainingParameters {
        var next = self

        switch adjustment {
        case .hold, .substituteRecovery:
            break

        case .runIntervalDistance(let delta):
            next.runIntervalDistanceMeters = max(
                runIntervalDistanceMeters + delta,
                Limits.minimumRunIntervalDistanceMeters
            )
            // Advance the hidden legacy proxy so run/walk can still graduate.
            next.runIntervalSeconds = max(runIntervalSeconds + 15, Limits.minimumRunIntervalSeconds)

        case .runWalkDistance(let delta):
            next.runWalkDistanceMeters = max(
                runWalkDistanceMeters + delta,
                Limits.minimumRunWalkDistanceMeters
            )
            next.runWalkSeconds = max(runWalkSeconds - 30, Limits.minimumRunWalkSeconds)

        case .graduateToContinuousRun:
            next.runIsContinuous = true
            let intervalWork = runIntervalDistanceMeters * Double(runRepeatCount)
            next.runContinuousDistanceMeters = max(
                Self.rounded(intervalWork * 0.75, to: 250),
                Limits.minimumContinuousRunDistanceMeters
            )
            next.runContinuousSeconds = max(
                (runIntervalSeconds * Double(runRepeatCount) / 2).rounded(),
                Limits.minimumContinuousRunSeconds
            )

        case .runContinuousDistance(let delta):
            next.runContinuousDistanceMeters = max(
                runContinuousDistanceMeters + delta,
                Limits.minimumContinuousRunDistanceMeters
            )
            next.runContinuousSeconds = max(runContinuousSeconds + 2 * 60, Limits.minimumContinuousRunSeconds)

        case .rideDistance(let delta):
            next.rideWorkDistanceMeters = max(
                rideWorkDistanceMeters + delta,
                Limits.minimumRideWorkDistanceMeters
            )
            next.rideWorkSeconds = max(rideWorkSeconds + 5 * 60, Limits.minimumRideWorkSeconds)

        // Legacy adjustment cases are still understood so old tests/debug
        // fixtures can be replayed safely, but new engines do not emit them.
        case .runIntervalDuration(let delta):
            next.runIntervalSeconds = max(runIntervalSeconds + delta, Limits.minimumRunIntervalSeconds)
        case .runWalkDuration(let delta):
            next.runWalkSeconds = max(runWalkSeconds + delta, Limits.minimumRunWalkSeconds)
        case .runContinuousDuration(let delta):
            next.runContinuousSeconds = max(runContinuousSeconds + delta, Limits.minimumContinuousRunSeconds)
        case .rideDuration(let delta):
            next.rideWorkSeconds = max(rideWorkSeconds + delta, Limits.minimumRideWorkSeconds)

        case .swimRestDuration(let delta):
            next.swimRestSeconds = max(
                swimRestSeconds + delta,
                Limits.restFloor(forRepeat: swimRepeatDistanceMeters)
            )

        case .swimRepeatDistance(let meters):
            next.swimRepeatDistanceMeters = meters
            next.swimRestSeconds = Limits.restFloor(forRepeat: meters) + Limits.restHeadroomSeconds
            next.swimTotalMeters = Self.roundedToRepeat(swimTotalMeters, repeatDistance: meters)

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

    private mutating func reduceVolume(by fraction: Double, for sport: Sport) {
        let remaining = 1 - min(max(fraction, 0), 1)

        switch sport {
        case .running:
            if runIsContinuous {
                runContinuousDistanceMeters = max(
                    Self.rounded(runContinuousDistanceMeters * remaining, to: 250),
                    Limits.minimumContinuousRunDistanceMeters
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
            rideWorkDistanceMeters = max(
                Self.rounded(rideWorkDistanceMeters * remaining, to: 500),
                Limits.minimumRideWorkDistanceMeters
            )
        }
    }

    private static func rounded(_ meters: Double, to increment: Double) -> Double {
        guard increment > 0 else { return meters }
        return (meters / increment).rounded() * increment
    }

    private static func roundedToRepeat(_ meters: Double, repeatDistance: Double) -> Double {
        guard repeatDistance > 0 else { return meters }
        return (meters / repeatDistance).rounded() * repeatDistance
    }
}
