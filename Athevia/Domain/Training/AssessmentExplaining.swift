import Foundation

/// Seam for the future explanation layer described in §20.
///
/// Intentionally not implemented. It exists so the engine can be wired to a
/// narrator later without reshaping anything: an explainer receives a decision
/// that has already been made and turns it into prose. It is never consulted
/// about what the decision should be.
protocol AssessmentExplaining: Sendable {
    func explanation(for assessment: WorkoutAssessment) async throws -> String
}

/// Deterministic explanation built from the assessment's own reasons.
///
/// Doubles as the fallback for when no LLM-backed explainer is configured.
struct DeterministicAssessmentExplainer: AssessmentExplaining {
    func explanation(for assessment: WorkoutAssessment) async throws -> String {
        let reasons = assessment.reasons.map(\.summary).joined(separator: ", ")
        let lead = reasons.isEmpty ? "No feedback was recorded" : reasons
        return "\(lead). Recommendation: \(assessment.adjustment.summary.lowercased())."
    }
}
