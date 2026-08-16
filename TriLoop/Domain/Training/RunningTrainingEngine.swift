import Foundation

/// Running progresses by lengthening the running interval only.
///
/// The walk recovery and the number of repeats are deliberately left alone, so
/// a progressing week changes exactly one variable. §13's worked example is
/// 1:00 → 1:15, which is the increment used here.
struct RunningTrainingEngine: SportTrainingEngine {
    let sport: Sport = .running
    var policy: TriagePolicy = .running
    var intervalIncrementSeconds: TimeInterval = 15

    func progressionAdjustment(result: WorkoutResult, feedback: FeedbackSummary) -> TrainingAdjustment {
        .runIntervalDuration(deltaSeconds: intervalIncrementSeconds)
    }
}
