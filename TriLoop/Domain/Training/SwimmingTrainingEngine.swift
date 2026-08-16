import Foundation

/// Swimming tightens rest before it adds distance.
///
/// Holding the same volume on less rest builds the continuous swimming and
/// breathing control a beginner actually lacks; adding metres first tends to
/// just add more broken 25s. Volume only increases once rest reaches the floor.
struct SwimmingTrainingEngine: SportTrainingEngine {
    let sport: Sport = .swimming
    var policy: TriagePolicy = .swimming
    var restDecrementSeconds: TimeInterval = 15
    var restFloorSeconds: TimeInterval = 30
    var volumeIncrementMeters: Double = 50

    func progressionAdjustment(result: WorkoutResult, feedback: FeedbackSummary) -> TrainingAdjustment {
        guard let rest = result.prescribedRestSeconds else {
            return .swimVolume(deltaMeters: volumeIncrementMeters)
        }
        if rest - restDecrementSeconds >= restFloorSeconds {
            return .swimRestDuration(deltaSeconds: -restDecrementSeconds)
        }
        return .swimVolume(deltaMeters: volumeIncrementMeters)
    }
}
