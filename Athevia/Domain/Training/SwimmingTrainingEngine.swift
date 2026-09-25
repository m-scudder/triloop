import Foundation

/// Swimming tightens rest, then lengthens the repeat, then adds volume.
///
/// Holding the same volume on less rest builds the continuous swimming and
/// breathing control a beginner actually lacks; adding metres first tends to
/// just add more broken 25s. Once rest reaches its floor the honest next step
/// is a longer repeat — that is what "swim further without stopping" means —
/// and volume only grows once the repeat cannot.
struct SwimmingTrainingEngine: SportTrainingEngine {
    let sport: Sport = .swimming
    var policy: TriagePolicy = .swimming
    var restDecrementSeconds: TimeInterval = 15
    var volumeIncrementMeters: Double = 50

    /// The pool being trained in. Repeats step up one length at a time so every
    /// repeat still finishes at a wall.
    var poolLengthMeters: Double = 25
    /// Longest repeat worth prescribing before the session is better described
    /// as continuous swimming, which is a different workout.
    var maximumRepeatMeters: Double = 200

    func progressionAdjustment(result: WorkoutResult, feedback: FeedbackSummary) -> TrainingAdjustment {
        guard let rest = result.prescribedRestSeconds else {
            return .swimVolume(deltaMeters: volumeIncrementMeters)
        }

        let repeatDistance = result.prescribedRepeatDistanceMeters ?? poolLengthMeters
        let pool = PoolLength(meters: poolLengthMeters)

        // A venue must never manufacture capability. If the current repeat is
        // shorter than one length of this pool, hold progression until the
        // athlete can safely use a shorter venue or demonstrates the full length.
        guard repeatDistance >= pool.meters else {
            return .hold
        }

        let floor = TrainingParameters.Limits.restFloor(forRepeat: repeatDistance)

        if rest - restDecrementSeconds >= floor {
            return .swimRestDuration(deltaSeconds: -restDecrementSeconds)
        }

        if let longer = nextRepeatDistance(after: repeatDistance) {
            return .swimRepeatDistance(meters: longer)
        }

        return .swimVolume(deltaMeters: volumeIncrementMeters)
    }

    /// One more length before resting. Returns `nil` once the repeat is as long
    /// as this progression prescribes.
    private func nextRepeatDistance(after current: Double) -> Double? {
        let pool = PoolLength(meters: poolLengthMeters)
        guard current >= pool.meters else { return nil }

        let next = current + pool.meters
        return next <= maximumRepeatMeters ? next : nil
    }
}
