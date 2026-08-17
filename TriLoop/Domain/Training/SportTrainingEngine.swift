import Foundation

/// Shared shape for the three sport engines.
///
/// Triage is common because GREEN / YELLOW / RED means the same thing in every
/// sport. What differs is the thresholds (`policy`) and the single lever each
/// sport pulls when the athlete has earned more work, which is the one thing a
/// conforming engine has to supply.
protocol SportTrainingEngine: Sendable {
    var sport: Sport { get }
    var policy: TriagePolicy { get }

    func progressionAdjustment(result: WorkoutResult, feedback: FeedbackSummary) -> TrainingAdjustment
}

extension SportTrainingEngine {
    func assess(
        result: WorkoutResult,
        feedback: FeedbackSummary,
        recovery: RecoverySummary? = nil
    ) -> WorkoutAssessment {
        let outcome = triage(result: result, feedback: feedback, recovery: recovery)
        return WorkoutAssessment(
            sport: sport,
            status: outcome.status,
            reasons: outcome.reasons,
            adjustment: adjustment(for: outcome.status, result: result, feedback: feedback)
        )
    }

    func adjustment(
        for status: AssessmentStatus,
        result: WorkoutResult,
        feedback: FeedbackSummary
    ) -> TrainingAdjustment {
        switch status {
        case .progress: progressionAdjustment(result: result, feedback: feedback)
        case .maintain: .hold
        case .reduce: .reduceVolume(fraction: policy.reductionFraction)
        case .recoveryRequired: .substituteRecovery
        }
    }

    func triage(
        result: WorkoutResult,
        feedback: FeedbackSummary,
        recovery: RecoverySummary? = nil
    ) -> (status: AssessmentStatus, reasons: [AssessmentReason]) {
        var reduceReasons: [AssessmentReason] = []

        if feedback.rpe >= policy.rpeRequiringReduction {
            reduceReasons.append(.effortTooHigh(rpe: feedback.rpe))
        }
        if result.completion < policy.lowCompletionThreshold {
            reduceReasons.append(.sessionLargelyMissed(completion: result.completion))
        }
        if feedback.painScore >= policy.painRequiringReduction {
            reduceReasons.append(.painReported(score: feedback.painScore))
        }
        if let recovery, recovery.painScore >= policy.painRequiringReduction {
            reduceReasons.append(.nextDayPain(score: recovery.painScore))
        }
        if !reduceReasons.isEmpty {
            return (.reduce, reduceReasons)
        }

        let completedEnough = result.completion >= policy.minimumCompletionForProgress
        let effortComfortable = feedback.rpe <= policy.maximumRPEForProgress
        let painAcceptable = feedback.painScore <= policy.maximumPainForProgress
        let recovered = feedback.recoveryFeeling.severity <= policy.worstRecoveryAllowingProgress.severity

        // A skipped check-in is not evidence of recovery, so absence never blocks.
        let nextDayClear = recovery.map { next in
            next.painScore <= policy.maximumNextDayPainForProgress
                && next.soreness.severity <= policy.worstSorenessAllowingProgress.severity
                && next.energy.severity <= policy.worstEnergyAllowingProgress.severity
        } ?? true

        if completedEnough, effortComfortable, painAcceptable, recovered, nextDayClear {
            var reasons: [AssessmentReason] = [
                result.completion >= 1 ? .completedAsPrescribed : .sessionIncomplete(completion: result.completion),
                .effortComfortable(rpe: feedback.rpe)
            ]
            reasons.append(feedback.painScore == 0 ? .noPainReported : .painReported(score: feedback.painScore))
            reasons.append(.recoveryAcceptable(feedback.recoveryFeeling))
            if recovery != nil {
                reasons.append(.recoveredOvernight)
            }
            return (.progress, reasons)
        }

        var reasons: [AssessmentReason] = []
        if !completedEnough { reasons.append(.sessionIncomplete(completion: result.completion)) }
        if !effortComfortable { reasons.append(.effortElevated(rpe: feedback.rpe)) }
        if !painAcceptable { reasons.append(.painReported(score: feedback.painScore)) }
        if !recovered { reasons.append(.recoveryIncomplete(feedback.recoveryFeeling)) }
        if let recovery, !nextDayClear {
            if recovery.painScore > policy.maximumNextDayPainForProgress {
                reasons.append(.nextDayPain(score: recovery.painScore))
            }
            if recovery.soreness.severity > policy.worstSorenessAllowingProgress.severity {
                reasons.append(.lingeringSoreness(recovery.soreness))
            }
            if recovery.energy.severity > policy.worstEnergyAllowingProgress.severity {
                reasons.append(.lowEnergyNextDay(recovery.energy))
            }
        }
        return (.maintain, reasons)
    }
}
