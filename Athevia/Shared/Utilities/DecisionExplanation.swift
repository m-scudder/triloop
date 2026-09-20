import Foundation

struct DecisionExplanation {
    struct Evidence: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let title: String
    let evidence: [Evidence]
    let reasons: [String]
    let change: String?

    var accessibilityLabel: String { title }

    static func weekly(_ sport: SportAnalysis, parameters: TrainingParameters? = nil) -> DecisionExplanation {
        DecisionExplanation(
            title: "Why \(sport.sport.displayName): \(sport.status.displayName)",
            evidence: [
                Evidence(label: "Reported sessions", value: "\(sport.completedSessions) / \(sport.plannedSessions)"),
                Evidence(label: "Average effort", value: sport.averageRPE.map {
                    "\($0.formatted(.number.precision(.fractionLength(0...1)))) / 10"
                } ?? "Not reported"),
                Evidence(label: "Highest reported pain", value: painValue(for: sport))
            ],
            reasons: sport.reasons.map(\.summary),
            change: change(for: sport, parameters: parameters)
        )
    }

    static func painValue(for sport: SportAnalysis) -> String {
        sport.completedSessions > 0 ? "\(sport.highestPain) / 10" : "Not reported"
    }

    static func change(for sport: SportAnalysis, parameters: TrainingParameters?) -> String {
        guard let before = parameters else { return sport.adjustment.summary }
        let after = before.applying(sport.adjustment, to: sport.sport)
        switch sport.adjustment {
        case .hold: return "No change"
        case .runIntervalDuration:
            return "Run interval: \(Int(before.runIntervalSeconds))s → \(Int(after.runIntervalSeconds))s"
        case .runWalkDuration:
            return "Walk: \(Int(before.runWalkSeconds))s → \(Int(after.runWalkSeconds))s"
        case .runContinuousDuration:
            return durationChange("Continuous run", before.runContinuousSeconds, after.runContinuousSeconds)
        case .rideDuration:
            return durationChange("Ride", before.rideWorkSeconds, after.rideWorkSeconds)
        case .swimRestDuration:
            return "Rest: \(Int(before.swimRestSeconds))s → \(Int(after.swimRestSeconds))s"
        case .swimRepeatDistance:
            return "Repeat: \(Int(before.swimRepeatDistanceMeters))m → \(Int(after.swimRepeatDistanceMeters))m"
        case .swimVolume:
            return "Distance: \(Int(before.swimTotalMeters))m → \(Int(after.swimTotalMeters))m"
        case .reduceVolume, .graduateToContinuousRun, .substituteRecovery:
            return sport.adjustment.summary
        }
    }

    private static func durationChange(_ label: String, _ before: TimeInterval, _ after: TimeInterval) -> String {
        "\(label): \(TrainingFormatter.totalDuration(seconds: before)) → \(TrainingFormatter.totalDuration(seconds: after))"
    }
}

extension AssessmentReason {
    var isSafetyCritical: Bool {
        switch self {
        case .painReported, .painRequiresEvaluation, .recoveryIncomplete, .warningSymptom,
             .nextDayPain, .lingeringSoreness, .lowEnergyNextDay, .effortTooHigh:
            true
        default:
            false
        }
    }
}