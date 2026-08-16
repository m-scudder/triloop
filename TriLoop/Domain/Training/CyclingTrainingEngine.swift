import Foundation

/// Cycling progresses on duration alone.
///
/// A flat five-minute step rather than §16's 5–10% because §15 specifies the
/// 30 → 35 → 40 → 45 ladder explicitly, and a percentage of a beginner's short
/// ride rounds to a meaninglessly small change. Speed is deliberately ignored.
struct CyclingTrainingEngine: SportTrainingEngine {
    let sport: Sport = .cycling
    var policy: TriagePolicy = .cycling
    var durationIncrementSeconds: TimeInterval = 5 * 60

    func progressionAdjustment(result: WorkoutResult, feedback: FeedbackSummary) -> TrainingAdjustment {
        .rideDuration(deltaSeconds: durationIncrementSeconds)
    }
}
