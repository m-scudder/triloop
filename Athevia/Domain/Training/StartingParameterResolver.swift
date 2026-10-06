import Foundation

/// Turns an athlete's self-assessment into the dials the engine trains on.
///
/// Deterministic and pure: the same assessment always produces the same first
/// week. This is the only place onboarding answers are interpreted — views
/// collect, this decides, the generator builds.
protocol StartingParameterResolving: Sendable {
    func resolve(
        baseline: AthleteBaseline,
        goal: TrainingGoal,
        poolLengthMeters: Double
    ) -> TrainingParameters
}

struct StartingParameterResolver: StartingParameterResolving {

    /// Starting sessions sit below what the athlete says they can already do.
    ///
    /// Week one exists to measure the response, not to find the ceiling. The
    /// engine then earns increases from reported effort, pain and recovery,
    /// which is a far better signal than a one-off self-assessment.
    func resolve(
        baseline: AthleteBaseline,
        goal: TrainingGoal,
        poolLengthMeters: Double
    ) -> TrainingParameters {
        var parameters = TrainingParameters()
        let caution = goal.startingCaution

        applyRunning(baseline.running, caution: caution, to: &parameters)
        applySwimming(
            baseline.swimming,
            stroke: baseline.stroke,
            poolLengthMeters: poolLengthMeters,
            caution: caution,
            to: &parameters
        )
        applyCycling(baseline.cycling, caution: caution, to: &parameters)

        return parameters
    }

    // MARK: - Running

    private func applyRunning(
        _ baseline: RunningBaseline,
        caution: Double,
        to parameters: inout TrainingParameters
    ) {
        parameters.runIsContinuous = baseline.runsContinuously

        switch baseline {
        case .none:
            parameters.runIntervalSeconds = 60
            parameters.runWalkSeconds = 120
            parameters.runRepeatCount = 5

        case .runWalk:
            parameters.runIntervalSeconds = 120
            parameters.runWalkSeconds = 60
            parameters.runRepeatCount = 5

        case .continuous10Minutes:
            parameters.runContinuousSeconds = scaledTrainingTime(10 * 60, by: caution, minimum: 5 * 60)

        case .continuous20To30Minutes:
            parameters.runContinuousSeconds = scaledTrainingTime(20 * 60, by: caution, minimum: 5 * 60)

        case .regular5K:
            parameters.runContinuousSeconds = scaledTrainingTime(30 * 60, by: caution, minimum: 5 * 60)
        }

        if !baseline.runsContinuously {
            parameters.runRepeatCount = max(
                Int((Double(parameters.runRepeatCount) * caution).rounded()),
                TrainingParameters.Limits.minimumRunRepeatCount
            )
        }
    }

    // MARK: - Swimming

    private func applySwimming(
        _ baseline: SwimmingBaseline,
        stroke: SwimStroke,
        poolLengthMeters: Double,
        caution: Double,
        to parameters: inout TrainingParameters
    ) {
        let pool = PoolLength(meters: poolLengthMeters)
        parameters.swimStroke = stroke
        parameters.swimPoolLengthMeters = pool.meters
        parameters.swimRepeatDistanceMeters = pool.repeatDistance(for: baseline)

        // Rest starts generous for a swimmer who cannot yet hold a length, and
        // tighter for one who can, because rest is the first lever the swim
        // engine tightens.
        parameters.swimRestSeconds = switch baseline {
        case .none, .continuous25: 45
        case .continuous50: 40
        case .continuous100, .continuous200Plus: 30
        }

        let target = switch baseline {
        case .none: 200.0
        case .continuous25: 300.0
        case .continuous50: 400.0
        case .continuous100: 600.0
        case .continuous200Plus: 800.0
        }

        parameters.swimTotalMeters = pool.roundedVolume(
            max(target * caution, TrainingParameters.Limits.minimumSwimMeters),
            repeatDistance: parameters.swimRepeatDistanceMeters
        )
    }

    // MARK: - Cycling

    private func applyCycling(
        _ baseline: CyclingBaseline,
        caution: Double,
        to parameters: inout TrainingParameters
    ) {
        parameters.rideWorkSeconds = scaledTrainingTime(
            TimeInterval(baseline.comfortableMinutes * 60),
            by: caution,
            minimum: TrainingParameters.Limits.minimumRideWorkSeconds
        )
    }

    private func scaledTrainingTime(
        _ seconds: TimeInterval,
        by caution: Double,
        minimum: TimeInterval
    ) -> TimeInterval {
        let scaled = seconds * caution
        if caution < 1 {
            let increment = TrainingParameters.Limits.trainingTimeIncrementSeconds
            let floored = (scaled / increment).rounded(.down) * increment
            return max(floored, minimum)
        }
        return TrainingParameters.normalizedTrainingTime(
            scaled,
            minimum: minimum
        )
    }
}
