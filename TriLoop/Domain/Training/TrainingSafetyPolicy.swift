import Foundation

/// The outcome of the safety check, which runs before any progression logic.
enum SafetyVerdict: Equatable, Sendable {
    case clear
    /// Training may continue, but the load must not increase.
    case blocksProgression([AssessmentReason])
    /// Training load is not the question. Rest and, where appropriate, get looked at.
    case requiresRecovery([AssessmentReason])

    var reasons: [AssessmentReason] {
        switch self {
        case .clear: []
        case .blocksProgression(let reasons), .requiresRecovery(let reasons): reasons
        }
    }
}

/// Rules the progression engines are not permitted to override.
///
/// TriLoop is a training application, not a diagnostic one. This policy does not
/// attempt to interpret what a symptom means; it only refuses to prescribe more
/// work when the athlete has reported something that training load cannot fix.
struct TrainingSafetyPolicy: Equatable, Sendable {
    /// At or above this, stop training and suggest professional evaluation.
    var painRequiringEvaluation: Int = 7
    /// At or above this, training continues but the load is frozen.
    var painBlockingProgression: Int = 2
    /// Feeling this depleted after an easy beginner session is itself a signal.
    var recoveryRequiringRest: RecoveryFeeling = .exhausted

    func evaluate(_ feedback: FeedbackSummary) -> SafetyVerdict {
        var stopping: [AssessmentReason] = feedback.symptoms
            .sorted { $0.rawValue < $1.rawValue }
            .map { .warningSymptom($0) }

        if feedback.painScore >= painRequiringEvaluation {
            stopping.append(.painRequiresEvaluation(score: feedback.painScore))
        }
        if feedback.recoveryFeeling.severity >= recoveryRequiringRest.severity {
            stopping.append(.recoveryIncomplete(feedback.recoveryFeeling))
        }
        if !stopping.isEmpty {
            return .requiresRecovery(stopping)
        }

        if feedback.painScore >= painBlockingProgression {
            return .blocksProgression([.painReported(score: feedback.painScore)])
        }
        return .clear
    }
}
