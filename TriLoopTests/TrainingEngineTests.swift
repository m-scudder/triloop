import Foundation
import Testing

@testable import TriLoop

@Suite("Training engine")
struct TrainingEngineTests {
    private let engine = TrainingEngine()

    // MARK: Running

    @Test("Easy, complete and painless running session progresses")
    func runningProgressesAfterAComfortableSession() {
        let assessment = engine.evaluate(
            // The interval is what marks this as run/walk rather than a
            // continuous run, and it is the lever that should move.
            result: WorkoutResult(sport: .running, completion: 1.0, prescribedIntervalSeconds: 60),
            feedback: FeedbackSummary(rpe: 3, painScore: 0, recoveryFeeling: .good)
        )

        #expect(assessment.status == .progress)
        #expect(assessment.adjustment == .runIntervalDuration(deltaSeconds: 15))
    }

    @Test("A session with no interval is already continuous and grows in duration")
    func continuousRunningGrowsInDuration() {
        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .running, completion: 1.0),
            feedback: FeedbackSummary(rpe: 3, painScore: 0, recoveryFeeling: .good)
        )

        #expect(assessment.adjustment == .runContinuousDuration(deltaSeconds: 120))
    }

    @Test("Hard but complete running session holds the workload")
    func runningMaintainsAfterAHardSession() {
        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .running, completion: 1.0),
            feedback: FeedbackSummary(rpe: 7, painScore: 1, recoveryFeeling: .okay)
        )

        #expect(assessment.status == .maintain)
        #expect(assessment.adjustment == .hold)
    }

    @Test("Failed running session with pain reduces the workload")
    func runningReducesAfterAFailedSession() {
        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .running, completion: 0.7),
            feedback: FeedbackSummary(rpe: 8, painScore: 5, painLocations: [.shin])
        )

        #expect(assessment.status == .reduce)
        #expect(assessment.adjustment == .reduceVolume(fraction: 0.2))
    }

    @Test("Running tolerates less pain than swimming before reducing")
    func runningReducesAtLowerPainThanSwimming() {
        let feedback = FeedbackSummary(rpe: 4, painScore: 3)

        let run = engine.evaluate(result: WorkoutResult(sport: .running, completion: 1.0), feedback: feedback)
        let swim = engine.evaluate(result: WorkoutResult(sport: .swimming, completion: 1.0), feedback: feedback)

        #expect(run.status == .reduce)
        #expect(swim.status == .maintain)
    }

    // MARK: Swimming

    @Test("Comfortable swim tightens rest before adding distance")
    func swimmingProgressesByTighteningRest() {
        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .swimming, completion: 1.0, distanceMeters: 300, prescribedRestSeconds: 45),
            feedback: FeedbackSummary(rpe: 4, painScore: 0, recoveryFeeling: .fresh)
        )

        #expect(assessment.status == .progress)
        #expect(assessment.adjustment == .swimRestDuration(deltaSeconds: -15))
    }

    @Test("Swim at the rest floor lengthens the repeat instead")
    func swimmingProgressesByContinuityOnceRestIsMinimal() {
        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .swimming, completion: 1.0, distanceMeters: 300, prescribedRestSeconds: 30),
            feedback: FeedbackSummary(rpe: 4, painScore: 0, recoveryFeeling: .fresh)
        )

        #expect(assessment.status == .progress)
        // Continuity before volume: swimming further without stopping is the
        // point, where more broken repeats is not.
        #expect(assessment.adjustment == .swimRepeatDistance(meters: 50))
    }

    @Test("Swimming still progresses at an effort that would hold running back")
    func swimmingToleratesAHigherEffort() {
        let feedback = FeedbackSummary(rpe: 6, painScore: 0, recoveryFeeling: .good)

        let swim = engine.evaluate(
            result: WorkoutResult(sport: .swimming, completion: 1.0, prescribedRestSeconds: 45),
            feedback: feedback
        )
        let run = engine.evaluate(result: WorkoutResult(sport: .running, completion: 1.0), feedback: feedback)

        #expect(swim.status == .progress)
        #expect(run.status == .maintain)
    }

    // MARK: Cycling

    @Test("Easy thirty minute ride earns five more minutes")
    func cyclingProgressesByDuration() {
        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .cycling, completion: 1.0, durationSeconds: 1800),
            feedback: FeedbackSummary(rpe: 3, painScore: 0, recoveryFeeling: .good)
        )

        #expect(assessment.status == .progress)
        #expect(assessment.adjustment == .rideDuration(deltaSeconds: 300))
    }

    @Test("Cycling ignores speed when deciding")
    func cyclingIgnoresPace() {
        let slow = engine.evaluate(
            result: WorkoutResult(sport: .cycling, completion: 1.0, durationSeconds: 1800, distanceMeters: 6_000),
            feedback: FeedbackSummary(rpe: 3)
        )
        let quick = engine.evaluate(
            result: WorkoutResult(sport: .cycling, completion: 1.0, durationSeconds: 1800, distanceMeters: 18_000),
            feedback: FeedbackSummary(rpe: 3)
        )

        #expect(slow.status == quick.status)
        #expect(slow.adjustment == quick.adjustment)
    }

    // MARK: Shared behaviour

    @Test("Each assessment carries the sport it was made for")
    func assessmentReportsItsSport() {
        for sport in Sport.allCases {
            let assessment = engine.evaluate(
                result: WorkoutResult(sport: sport, completion: 1.0),
                feedback: FeedbackSummary(rpe: 3)
            )
            #expect(assessment.sport == sport)
        }
    }

    @Test("A progressing assessment always explains itself")
    func progressingAssessmentsCarryReasons() {
        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .running, completion: 1.0),
            feedback: FeedbackSummary(rpe: 3, painScore: 0, recoveryFeeling: .fresh)
        )

        #expect(assessment.reasons.contains(.completedAsPrescribed))
        #expect(assessment.reasons.contains(.effortComfortable(rpe: 3)))
        #expect(assessment.reasons.contains(.noPainReported))
        #expect(assessment.reasons.isEmpty == false)
    }
}
