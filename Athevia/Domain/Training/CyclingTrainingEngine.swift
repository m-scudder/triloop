import Foundation

/// Cycling progresses by distance. Speed is deliberately ignored: the athlete
/// earns a longer prescribed ride only from completion, effort and recovery.
struct CyclingTrainingEngine: SportTrainingEngine {
    let sport: Sport = .cycling
    var policy: TriagePolicy = .cycling
    var distanceIncrementMeters: Double = 1_000

    func progressionAdjustment(result: WorkoutResult, feedback: FeedbackSummary) -> TrainingAdjustment {
        .rideDistance(deltaMeters: distanceIncrementMeters)
    }
}
