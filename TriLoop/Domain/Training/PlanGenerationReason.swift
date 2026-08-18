import Foundation

/// Why a plan looks the way it does.
///
/// The existing free-text `generationReason` stays as the human sentence; this
/// is the machine-readable companion, so a future explanation layer can reason
/// about the cause rather than parse prose.
enum PlanGenerationReason: String, Codable, CaseIterable, Sendable {
    case initialAssessment
    case weeklyProgression
    case weeklyMaintain
    case weeklyReduction
    case recovery
    case availabilityChanged
    case profileChanged

    var displayName: String {
        switch self {
        case .initialAssessment: "First week from your setup"
        case .weeklyProgression: "Progressed from last week"
        case .weeklyMaintain: "Holding last week's load"
        case .weeklyReduction: "Reduced after last week"
        case .recovery: "Recovery week"
        case .availabilityChanged: "Rebuilt around your availability"
        case .profileChanged: "Rebuilt after a profile change"
        }
    }

    /// The reason a week's verdicts imply, so the generator never has to invent
    /// one. The most cautious outcome wins, matching how the analyser already
    /// lets the worst session govern the week.
    static func from(_ statuses: [AssessmentStatus]) -> PlanGenerationReason {
        if statuses.contains(.recoveryRequired) { return .recovery }
        if statuses.contains(.reduce) { return .weeklyReduction }
        if statuses.contains(.progress) { return .weeklyProgression }
        return .weeklyMaintain
    }
}
