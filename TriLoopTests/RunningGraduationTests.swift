import Foundation
import Testing

@testable import TriLoop

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

        #expect(adjustment == .runIntervalDuration(deltaSeconds: 15))
    }

    @Test("Once the interval is long enough the walk shrinks instead")
    func longIntervalsShortenTheWalk() {
        let adjustment = engine.progressionAdjustment(
            result: result(interval: 300, walk: 120), feedback: easy
        )

        #expect(adjustment == .runWalkDuration(deltaSeconds: -30))
    }

    @Test("With the walk at its floor, running becomes continuous")
    func minimalWalkGraduates() {
        let adjustment = engine.progressionAdjustment(
            result: result(interval: 300, walk: 30), feedback: easy
        )

        #expect(adjustment == .graduateToContinuousRun)
    }

    @Test("A continuous run grows by duration")
    func continuousRunsAddMinutes() {
        let adjustment = engine.progressionAdjustment(
            result: result(interval: nil, walk: nil), feedback: easy
        )

        #expect(adjustment == .runContinuousDuration(deltaSeconds: 120))
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
        parameters.runRepeatCount = 6

        let graduated = parameters.applying(.graduateToContinuousRun, to: .running)

        // 6 × 5:00 broken up becomes 15 minutes unbroken, not 30.
        #expect(graduated.runIsContinuous)
        #expect(graduated.runContinuousSeconds == 900)
    }

    @Test("A continuous run reduces by duration, not by repeats")
    func reductionUsesDurationOnceContinuous() {
        var parameters = TrainingParameters()
        parameters.runIsContinuous = true
        parameters.runContinuousSeconds = 20 * 60

        let reduced = parameters.applying(.reduceVolume(fraction: 0.2), to: .running)

        #expect(reduced.runContinuousSeconds == TimeInterval(16 * 60))
        #expect(reduced.runRepeatCount == parameters.runRepeatCount)
    }

    @Test("A continuous run is built as one block")
    func continuousTemplateHasNoIntervals() {
        var parameters = TrainingParameters()
        parameters.runIsContinuous = true
        parameters.runContinuousSeconds = 900

        let workout = WorkoutTemplates.runWalk(on: .now, parameters: parameters)

        #expect(workout.orderedSteps.contains { $0.kind == .repeatBlock } == false)
        #expect(workout.estimatedDurationSeconds == TimeInterval(900 + 600))
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
        // Added after this payload was written; the default keeps it usable.
        #expect(decoded.swimPoolLengthMeters == 25)
    }
}
