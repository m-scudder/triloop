import Foundation
import Testing

@testable import TriLoop

@Suite("Training safety policy")
struct TrainingSafetyPolicyTests {
    private let policy = TrainingSafetyPolicy()

    @Test("An unremarkable session is clear")
    func easySessionIsClear() {
        #expect(policy.evaluate(FeedbackSummary(rpe: 3, painScore: 0)) == .clear)
    }

    @Test("Warning symptoms require recovery regardless of effort")
    func warningSymptomsRequireRecovery() {
        for symptom in WarningSymptom.allCases {
            let verdict = policy.evaluate(
                FeedbackSummary(rpe: 2, painScore: 0, recoveryFeeling: .fresh, symptoms: [symptom])
            )

            #expect(verdict == .requiresRecovery([.warningSymptom(symptom)]))
        }
    }

    @Test("Severe pain requires recovery")
    func severePainRequiresRecovery() {
        let verdict = policy.evaluate(FeedbackSummary(rpe: 4, painScore: 7))

        #expect(verdict == .requiresRecovery([.painRequiresEvaluation(score: 7)]))
    }

    @Test("Exhaustion requires recovery")
    func exhaustionRequiresRecovery() {
        let verdict = policy.evaluate(FeedbackSummary(rpe: 4, recoveryFeeling: .exhausted))

        #expect(verdict == .requiresRecovery([.recoveryIncomplete(.exhausted)]))
    }

    @Test("Moderate pain freezes the load without demanding rest")
    func moderatePainBlocksProgression() {
        let verdict = policy.evaluate(FeedbackSummary(rpe: 4, painScore: 3))

        #expect(verdict == .blocksProgression([.painReported(score: 3)]))
    }
}

@Suite("Safety overrides progression")
struct SafetyOverrideTests {
    @Test("A flawless session is still sent to recovery when a symptom is reported")
    func symptomOverridesAPerfectSession() {
        let engine = TrainingEngine()

        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .running, completion: 1.0),
            feedback: FeedbackSummary(rpe: 2, painScore: 0, recoveryFeeling: .fresh, symptoms: [.dizziness])
        )

        #expect(assessment.status == .recoveryRequired)
        #expect(assessment.adjustment == .substituteRecovery)
        #expect(assessment.recommendsHarderTraining == false)
    }

    /// Guards the layering rather than the numbers: even if the triage
    /// thresholds are later loosened until a painful session would qualify for
    /// progression, the safety policy must still refuse the increase.
    @Test("Safety blocks progression even when triage would allow it")
    func safetyVetoesAMisTunedTriagePolicy() {
        var permissive = TriagePolicy.running
        permissive.maximumPainForProgress = 10
        permissive.painRequiringReduction = 10

        let engine = TrainingEngine(running: RunningTrainingEngine(policy: permissive))
        let feedback = FeedbackSummary(rpe: 3, painScore: 3, painLocations: [.knee])

        let unguarded = RunningTrainingEngine(policy: permissive)
            .assess(result: WorkoutResult(sport: .running, completion: 1.0), feedback: feedback)
        let guarded = engine.evaluate(result: WorkoutResult(sport: .running, completion: 1.0), feedback: feedback)

        #expect(unguarded.status == .progress)
        #expect(guarded.status == .maintain)
        #expect(guarded.adjustment == .hold)
        #expect(guarded.reasons.contains(.painReported(score: 3)))
    }

    @Test("Recovery-required assessments never carry a progression adjustment")
    func recoveryNeverProgresses() {
        let engine = TrainingEngine()

        for sport in Sport.allCases {
            let assessment = engine.evaluate(
                result: WorkoutResult(sport: sport, completion: 1.0, prescribedRestSeconds: 45),
                feedback: FeedbackSummary(rpe: 2, painScore: 9, recoveryFeeling: .fresh)
            )

            #expect(assessment.status == .recoveryRequired)
            #expect(assessment.adjustment == .substituteRecovery)
        }
    }
}
