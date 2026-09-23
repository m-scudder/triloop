import Foundation

/// Coarse compatibility goal consumed by the existing adaptive engine.
///
/// New athlete intent is stored in TrainingObjective. This enum remains stable
/// so existing profiles, first-week resolution and weekly progression keep
/// their established contract until the journey layer is added above them.
enum TrainingGoal: String, Codable, CaseIterable, Sendable {
    case generalFitness
    case firstTriathlon
    case improveEndurance
    case returnToTraining

    var displayName: String {
        switch self {
        case .generalFitness: "General Fitness"
        case .firstTriathlon: "First Triathlon"
        case .improveEndurance: "Improve Endurance"
        case .returnToTraining: "Return to Training"
        }
    }

    var detail: String {
        switch self {
        case .generalFitness: "Train across all three sports without a race in mind."
        case .firstTriathlon: "Build towards swimming, riding and running in one event."
        case .improveEndurance: "Go further and for longer than you can today."
        case .returnToTraining: "Rebuild after time away, without picking up where you left off."
        }
    }

    /// How much to hold back the starting prescription.
    ///
    /// Returning athletes remember what they used to do and tend to start
    /// there, so their first week is deliberately lighter than their stated
    /// ability. A goal never makes training *harder* — that is progression's
    /// job, earned week by week.
    var startingCaution: Double {
        switch self {
        case .returnToTraining: 0.8
        case .generalFitness, .improveEndurance, .firstTriathlon: 1.0
        }
    }
}
