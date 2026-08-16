import Foundation

/// Entry point for evaluating a single completed session.
///
/// Ordering matters: the safety policy runs first and its verdict cannot be
/// overridden by a sport engine. A sport engine is never even consulted when the
/// athlete has reported something that rest, not a different workload, answers.
struct TrainingEngine: Sendable {
    var safetyPolicy: TrainingSafetyPolicy = TrainingSafetyPolicy()
    var running: RunningTrainingEngine = RunningTrainingEngine()
    var swimming: SwimmingTrainingEngine = SwimmingTrainingEngine()
    var cycling: CyclingTrainingEngine = CyclingTrainingEngine()

    func evaluate(result: WorkoutResult, feedback: FeedbackSummary) -> WorkoutAssessment {
        let verdict = safetyPolicy.evaluate(feedback)

        if case .requiresRecovery(let reasons) = verdict {
            return WorkoutAssessment(
                sport: result.sport,
                status: .recoveryRequired,
                reasons: reasons,
                adjustment: .substituteRecovery
            )
        }

        let assessment = engine(for: result.sport).assess(result: result, feedback: feedback)

        // Safety can veto an increase, but it never manufactures one.
        if case .blocksProgression(let reasons) = verdict, assessment.status == .progress {
            return WorkoutAssessment(
                sport: assessment.sport,
                status: .maintain,
                reasons: reasons + assessment.reasons,
                adjustment: .hold
            )
        }

        return assessment
    }

    func engine(for sport: Sport) -> any SportTrainingEngine {
        switch sport {
        case .running: running
        case .swimming: swimming
        case .cycling: cycling
        }
    }
}
