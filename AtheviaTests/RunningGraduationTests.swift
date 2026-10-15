import Foundation
import Testing

@testable import Athevia

@Suite("Running graduation")
struct RunningGraduationTests {
    private let engine = RunningTrainingEngine()

    private let easy = FeedbackSummary(rpe: 3, painScore: 0, recoveryFeeling: .good)

    private func result(interval: TimeInterval?, walk: TimeInterval?) -> WorkoutResult {
        WorkoutResult(
            sport: .running,
            completion: 1,
            prescribedRestSeconds: walk,
            prescribedIntervalSeconds: interval
        )
    }

    @Test("Short intervals grow before anything else changes")
    func earlyProgressionLengthensTheInterval() {
        let adjustment = engine.progressionAdjustment(
            result: result(interval: 60, walk: 120), feedback: easy
        )

        #expect(adjustment == .runIntervalDistance(deltaMeters: 50))
    }

    @Test("Once the interval is long enough the walk shrinks instead")
    func longIntervalsShortenTheWalk() {
        let adjustment = engine.progressionAdjustment(
            result: result(interval: 300, walk: 120), feedback: easy
        )

        #expect(adjustment == .runWalkDistance(deltaMeters: -25))
    }

    @Test("With the walk at its floor, running becomes continuous")
    func minimalWalkGraduates() {
        let adjustment = engine.progressionAdjustment(
            result: result(interval: 300, walk: 30), feedback: easy
        )

        #expect(adjustment == .graduateToContinuousRun)
    }

    @Test("A continuous run grows by distance")
    func continuousRunsAddDistance() {
        let adjustment = engine.progressionAdjustment(
            result: result(interval: nil, walk: nil), feedback: easy
        )

        #expect(adjustment == .runContinuousDistance(deltaMeters: 250))
    }

    @Test("The interval never grows without limit")
    func intervalStopsGrowing() {
        var parameters = TrainingParameters()

        // Twenty progressions is far more than the interval phase should absorb.
        for _ in 0..<20 {
            let adjustment = engine.progressionAdjustment(
                result: result(
                    interval: parameters.runIsContinuous ? nil : parameters.runIntervalSeconds,
                    walk: parameters.runIsContinuous ? nil : parameters.runWalkSeconds
                ),
                feedback: easy
            )
            parameters = parameters.applying(adjustment, to: .running)
        }

        #expect(parameters.runIsContinuous)
        #expect(parameters.runIntervalSeconds <= 300)
    }

    @Test("Graduating keeps the running honest rather than doubling it")
    func graduationHalvesTheIntervalWork() {
        var parameters = TrainingParameters()
        parameters.runIntervalSeconds = 300
        parameters.runIntervalDistanceMeters = 500
        parameters.runRepeatCount = 6

        let graduated = parameters.applying(.graduateToContinuousRun, to: .running)

        // Broken intervals become a conservative continuous-distance target.
        #expect(graduated.runIsContinuous)
        #expect(graduated.runContinuousDistanceMeters == 2_250)
    }

    @Test("A continuous run reduces by distance, not by repeats")
    func reductionUsesDistanceOnceContinuous() {
        var parameters = TrainingParameters()
        parameters.runIsContinuous = true
        parameters.runContinuousDistanceMeters = 5_000

        let reduced = parameters.applying(.reduceVolume(fraction: 0.2), to: .running)

        #expect(reduced.runContinuousDistanceMeters == 4_000)
        #expect(reduced.runRepeatCount == parameters.runRepeatCount)
    }

    @Test("A continuous run is built as one block")
    func continuousTemplateHasNoIntervals() {
        var parameters = TrainingParameters()
        parameters.runIsContinuous = true
        parameters.runContinuousDistanceMeters = 2_000

        let workout = PrescribedSessions.runWalk(on: .now, parameters: parameters)

        #expect(workout.orderedSteps.contains { $0.kind == .repeatBlock } == false)
        #expect(workout.targetDistanceMeters == 2_500)
        #expect(workout.orderedSteps.allSatisfy { $0.distanceMeters != nil })
    }

    @Test("Parameters stored before continuous running still decode")
    func olderParametersDecode() throws {
        let legacy = """
        {
            "runWarmUpSeconds": 300,
            "runIntervalSeconds": 75,
            "runWalkSeconds": 120,
            "runRepeatCount": 6,
            "runCooldownSeconds": 300,
            "swimRepeatDistanceMeters": 25,
            "swimTotalMeters": 300,
            "swimRestSeconds": 30,
            "rideWarmUpSeconds": 300,
            "rideWorkSeconds": 1500,
            "rideCooldownSeconds": 300
        }
        """

        let decoded = try JSONDecoder().decode(
            TrainingParameters.self,
            from: Data(legacy.utf8)
        )

        #expect(decoded.runIntervalSeconds == 75)
        #expect(decoded.runIsContinuous == false)
        #expect(decoded.runContinuousSeconds == 0)
        #expect(decoded.runIntervalDistanceMeters == 150)
        #expect(decoded.rideWorkDistanceMeters == 3_000)
        // Added after this payload was written; defaults keep it usable.
        #expect(decoded.swimPoolLengthMeters == 25)
    }
}
