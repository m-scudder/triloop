import Foundation
import Testing

@testable import TriLoop

@Suite("Explanation presentation")
struct ExplanationPresentationTests {
    @Test(arguments: TrainingConceptExplanation.allCases)
    func conceptsHaveContentAndAccessibleLabels(_ concept: TrainingConceptExplanation) {
        #expect(!concept.title.isEmpty)
        #expect(!concept.definition.isEmpty)
        #expect(!concept.usage.isEmpty)
        #expect(concept.accessibilityLabel.contains(concept.title.lowercased()))
    }

    @Test func unknownConceptIsNotInvented() {
        #expect(TrainingConceptExplanation(rawValue: "unknown") == nil)
    }

    @Test func missingReportsAreNotZeroPainOrEffort() {
        let sport = analysis(completed: 0, rpe: nil, pain: 0)
        let explanation = DecisionExplanation.weekly(sport)
        #expect(explanation.evidence[1].value == "Not reported")
        #expect(explanation.evidence[2].value == "Not reported")
        #expect(explanation.reasons == sport.reasons.map(\.summary))
    }

    @Test func decisionUsesActualReportedEvidence() {
        let sport = analysis(completed: 1, rpe: 8, pain: 3)
        let explanation = DecisionExplanation.weekly(sport)
        #expect(explanation.evidence[0].value == "1 / 2")
        #expect(explanation.evidence[1].value == "8 / 10")
        #expect(explanation.evidence[2].value == "3 / 10")
        #expect(explanation.change == sport.adjustment.summary)
        #expect(explanation.accessibilityLabel.contains(sport.sport.displayName))
        #expect(explanation.accessibilityLabel.contains(sport.status.displayName))
    }

    @Test func painAndRecoveryReasonsStayVisible() {
        #expect(AssessmentReason.painReported(score: 3).isSafetyCritical)
        #expect(AssessmentReason.painRequiresEvaluation(score: 7).isSafetyCritical)
        #expect(AssessmentReason.nextDayPain(score: 4).isSafetyCritical)
        #expect(AssessmentReason.recoveryIncomplete(.exhausted).isSafetyCritical)
        #expect(!AssessmentReason.completedAsPrescribed.isSafetyCritical)
        #expect(!AssessmentReason.noPainReported.isSafetyCritical)
    }

    @Test(arguments: [IntensityEvidence.reportedEffort, .healthKitEffort])
    func effortOnlyDoesNotClaimHeartRateAgreement(_ evidence: IntensityEvidence) {
        let reading = WorkoutIntensityReading(intensity: .easy, evidence: evidence)
        let explanation = WorkoutEvidencePresentation.intensity(reading)
        #expect(explanation.evidence[0].value == WorkoutEvidencePresentation.source(evidence))
        #expect(explanation.reasons == [WorkoutEvidencePresentation.reason(evidence)])
        #expect(!explanation.reasons[0].contains("agree"))
        #expect(explanation.reasons[0].contains("heart-rate evidence was not used"))
    }

    @Test func combinedEvidenceDoesNotInventAnAthleteReport() {
        let explanation = WorkoutEvidencePresentation.reason(.hybrid)
        #expect(!explanation.contains("reported"))
        #expect(WorkoutEvidencePresentation.source(IntensityEvidence.conflicting) == "Sources disagree")
    }

    @Test func generatedProvenanceIsUnobtrusive() {
        #expect(WorkoutEvidencePresentation.provenance(.generated) == nil)
        for origin in [WorkoutOrigin.library, .custom, .imported] {
            #expect(WorkoutEvidencePresentation.provenance(origin)?.isEmpty == false)
        }
    }

    @Test func displayedChangeRespectsTheActualAdjustmentFloor() {
        let parameters = TrainingParameters()
        let sport = SportAnalysis(
            sport: .swimming, status: .progress, plannedSessions: 2,
            completedSessions: 2, averageRPE: 3, highestPain: 0,
            totalDurationSeconds: 0, totalDistanceMeters: 600,
            reasons: [.noPainReported], adjustment: .swimRestDuration(deltaSeconds: -30)
        )
        let next = parameters.applying(sport.adjustment, to: .swimming)
        let explanation = DecisionExplanation.weekly(sport, parameters: parameters)
        #expect(next.swimRestSeconds == 30)
        #expect(explanation.change?.contains("45s → 30s") == true)
        #expect(parameters.swimRestSeconds == 45)
    }

    private func analysis(completed: Int, rpe: Double?, pain: Int) -> SportAnalysis {
        SportAnalysis(
            sport: .running, status: .maintain, plannedSessions: 2,
            completedSessions: completed, averageRPE: rpe, highestPain: pain,
            totalDurationSeconds: 0, totalDistanceMeters: 0,
            reasons: [.sessionsMissed(count: 2 - completed)], adjustment: .hold
        )
    }
}