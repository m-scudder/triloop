import Foundation

/// Running progresses through three phases, changing one variable at a time.
///
/// 1. Lengthen the running interval, leaving the count and walk alone (§13).
/// 2. Once the interval is long enough, shorten the walk instead.
/// 3. When the walk is minimal, drop it and run continuously.
///
/// Without the last two phases the interval would grow without limit, and a
/// beginner plan would still be prescribing walk breaks after an hour of running.
struct RunningTrainingEngine: SportTrainingEngine {
    let sport: Sport = .running
    var policy: TriagePolicy = .running
    var intervalIncrementSeconds: TimeInterval = 15
    /// Interval length at which walk breaks start being reduced instead.
    var graduationIntervalSeconds: TimeInterval = 5 * 60
    var walkDecrementSeconds: TimeInterval = 30
    var walkFloorSeconds: TimeInterval = 30
    var continuousIncrementSeconds: TimeInterval = 2 * 60

    func progressionAdjustment(result: WorkoutResult, feedback: FeedbackSummary) -> TrainingAdjustment {
        // No interval means the session is already one continuous run.
        guard let interval = result.prescribedIntervalSeconds else {
            return .runContinuousDuration(deltaSeconds: continuousIncrementSeconds)
        }

        if interval < graduationIntervalSeconds {
            return .runIntervalDuration(deltaSeconds: intervalIncrementSeconds)
        }

        let walk = result.prescribedRestSeconds ?? 0
        if walk - walkDecrementSeconds >= walkFloorSeconds {
            return .runWalkDuration(deltaSeconds: -walkDecrementSeconds)
        }

        return .graduateToContinuousRun
    }
}
