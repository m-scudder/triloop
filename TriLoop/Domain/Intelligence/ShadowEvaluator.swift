import Foundation

/// A non-authoritative second opinion on a week (§51).
///
/// §52 is unambiguous: the existing engine remains the source of progress,
/// maintain, reduce and recoveryRequired. Nothing here is wired into that
/// decision, and nothing may be. It exists so future phases can be judged
/// against recorded evidence rather than intuition.
struct ShadowObservation: Equatable, Sendable {
    /// What the current engine decided, for comparison.
    let engineDecision: String
    /// What the signals would suggest, if anything.
    let suggestion: Suggestion
    /// The readings that led there, in the athlete's own terms.
    let reasons: [String]

    enum Suggestion: String, Equatable, Sendable {
        case agrees
        case maintainMayBeMoreAppropriate
        case reduceMayBeMoreAppropriate
        case insufficientEvidence
    }
}

/// Compares the engine's decision with what the signals imply.
enum ShadowEvaluator {

    /// Week-on-week load growth beyond which a rise is worth noticing.
    ///
    /// Chosen to sit above ordinary progression, which moves one dial at a time
    /// and rarely shifts a week's total by a fifth.
    static let sharpLoadRise = 0.20

    static func evaluate(
        signals: TrainingSignals,
        engineDecision: String
    ) -> ShadowObservation {
        var reasons: [String] = []
        var concerns = 0

        if let change = signals.workload.weekOnWeekChange, change > sharpLoadRise {
            reasons.append("Weekly load is up \(Int((change * 100).rounded()))% on last week.")
            concerns += 1
        }

        if signals.adherence.aboveTargetCount > 0 {
            let count = signals.adherence.aboveTargetCount
            reasons.append("\(count) session\(count == 1 ? "" : "s") went above target.")
            concerns += 1
        }

        for metric in signals.recovery.outsideUsualRange {
            guard let standing = signals.recovery.standings[metric] else { continue }
            reasons.append(description(of: metric, standing: standing))
            if isUnfavourable(metric, standing) { concerns += 1 }
        }

        // No evidence at all is not agreement: it is silence, and §55 requires
        // the difference to be visible.
        guard !signals.isEmpty else {
            return ShadowObservation(
                engineDecision: engineDecision,
                suggestion: .insufficientEvidence,
                reasons: ["Not enough measured training to form a view."]
            )
        }

        let suggestion: ShadowObservation.Suggestion = switch concerns {
        case 0: .agrees
        case 1: .maintainMayBeMoreAppropriate
        default: .reduceMayBeMoreAppropriate
        }

        return ShadowObservation(
            engineDecision: engineDecision,
            suggestion: suggestion,
            reasons: reasons.isEmpty ? ["No signal stood out this week."] : reasons
        )
    }

    /// Whether a reading sitting outside its range is the worrying direction.
    ///
    /// A resting heart rate above baseline and an HRV below it point the same
    /// way; treating both as simply "outside range" would lose that.
    private static func isUnfavourable(_ metric: RecoveryMetricKey, _ standing: BaselineStanding) -> Bool {
        switch metric {
        case .restingHeartRate: standing == .above
        case .heartRateVariability, .sleepDuration, .cardioFitness, .heartRateRecovery: standing == .below
        }
    }

    private static func description(of metric: RecoveryMetricKey, standing: BaselineStanding) -> String {
        let name = switch metric {
        case .restingHeartRate: "Resting heart rate"
        case .heartRateVariability: "HRV"
        case .sleepDuration: "Sleep"
        case .cardioFitness: "Cardio fitness"
        case .heartRateRecovery: "Heart rate recovery"
        }

        return switch standing {
        case .above: "\(name) is above your recent range."
        case .below: "\(name) is below your recent range."
        case .withinRange: "\(name) is within your recent range."
        }
    }
}
