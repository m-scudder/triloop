import Foundation

/// Running progresses through distance-based run/walk work before graduating
/// to continuous distance. Time fields are no longer prescribed to the athlete.
struct RunningTrainingEngine: SportTrainingEngine {
    let sport: Sport = .running
    var policy: TriagePolicy = .running
    var intervalIncrementMeters: Double = 50
    /// Hidden legacy interval proxy used only to preserve the existing
    /// graduation cadence for older capability/history logic.
    var graduationIntervalSeconds: TimeInterval = 5 * 60
    var walkDecrementMeters: Double = 25
    var walkFloorMeters: Double = 50
    var continuousIncrementMeters: Double = 250

    func progressionAdjustment(result: WorkoutResult, feedback: FeedbackSummary) -> TrainingAdjustment {
        guard let interval = result.prescribedIntervalSeconds else {
            return .runContinuousDistance(deltaMeters: continuousIncrementMeters)
        }

        if interval < graduationIntervalSeconds {
            return .runIntervalDistance(deltaMeters: intervalIncrementMeters)
        }

        let walkSeconds = result.prescribedRestSeconds ?? 0
        if walkSeconds > 30 {
            return .runWalkDistance(deltaMeters: -walkDecrementMeters)
        }

        return .graduateToContinuousRun
    }
}
