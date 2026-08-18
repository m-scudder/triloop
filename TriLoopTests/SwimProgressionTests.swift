import Foundation
import Testing

@testable import TriLoop

@Suite("Swim progression")
struct SwimProgressionTests {

    private func engine(pool: Double = 25) -> SwimmingTrainingEngine {
        SwimmingTrainingEngine(poolLengthMeters: pool)
    }

    private func result(rest: TimeInterval, repeatDistance: Double) -> WorkoutResult {
        WorkoutResult(
            sport: .swimming,
            completion: 1,
            prescribedRestSeconds: rest,
            prescribedRepeatDistanceMeters: repeatDistance
        )
    }

    private let easy = FeedbackSummary(
        rpe: 3,
        painScore: 0,
        painLocations: [],
        recoveryFeeling: .good,
        symptoms: [],
        notes: ""
    )

    @Test("Rest tightens before anything else changes")
    func restIsTheFirstLever() {
        let adjustment = engine().progressionAdjustment(
            result: result(rest: 45, repeatDistance: 25),
            feedback: easy
        )

        #expect(adjustment == .swimRestDuration(deltaSeconds: -15))
    }

    @Test("Once rest is at its floor the repeat lengthens")
    func repeatLengthensAtRestFloor() {
        let adjustment = engine().progressionAdjustment(
            result: result(rest: 30, repeatDistance: 25),
            feedback: easy
        )

        #expect(adjustment == .swimRepeatDistance(meters: 50))
    }

    @Test("A repeat steps up by one pool length, not an arbitrary amount")
    func repeatStepsByPoolLength() {
        let longPool = engine(pool: 50).progressionAdjustment(
            result: result(rest: 60, repeatDistance: 50),
            feedback: easy
        )

        #expect(longPool == .swimRepeatDistance(meters: 100))
    }

    @Test("A repeat shorter than the pool steps up to a whole length")
    func shortRepeatReachesTheWall() {
        // 25 m ability in a 50 m pool: the next step is a full length.
        let adjustment = engine(pool: 50).progressionAdjustment(
            result: result(rest: 30, repeatDistance: 25),
            feedback: easy
        )

        #expect(adjustment == .swimRepeatDistance(meters: 50))
    }

    @Test("Volume grows only once the repeat cannot")
    func volumeIsTheLastLever() {
        var swim = engine()
        swim.maximumRepeatMeters = 100

        let adjustment = swim.progressionAdjustment(
            result: result(rest: 90, repeatDistance: 100),
            feedback: easy
        )

        #expect(adjustment == .swimVolume(deltaMeters: 50))
    }

    @Test("The rest floor rises with the repeat distance")
    func restFloorScalesWithRepeat() {
        #expect(TrainingParameters.Limits.restFloor(forRepeat: 25) == 30)
        #expect(TrainingParameters.Limits.restFloor(forRepeat: 50) == 60)
        #expect(TrainingParameters.Limits.restFloor(forRepeat: 200) == 90)
    }

    @Test("Stepping the repeat up changes one lever, leaving volume intact")
    func repeatStepPreservesVolume() {
        var parameters = TrainingParameters()
        parameters.swimRepeatDistanceMeters = 25
        parameters.swimTotalMeters = 300
        parameters.swimRestSeconds = 30

        let next = parameters.applying(.swimRepeatDistance(meters: 50), to: .swimming)

        #expect(next.swimRepeatDistanceMeters == 50)
        #expect(next.swimTotalMeters == 300)
        // Rest is not tightened by a structural step; the floor simply rises.
        #expect(next.swimRestSeconds == 60)
    }

    @Test("A longer repeat leaves room to tighten rest again next week")
    func steppingUpRestoresTheRestLever() {
        let stepped = TrainingParameters().applying(.swimRepeatDistance(meters: 50), to: .swimming)

        let adjustment = engine(pool: 50).progressionAdjustment(
            result: result(rest: stepped.swimRestSeconds + 15, repeatDistance: 50),
            feedback: easy
        )

        #expect(adjustment == .swimRestDuration(deltaSeconds: -15))
    }

    @Test("Volume stays in whole repeats after a step up")
    func volumeStaysInWholeRepeats() {
        var parameters = TrainingParameters()
        parameters.swimRepeatDistanceMeters = 25
        parameters.swimTotalMeters = 325

        let next = parameters.applying(.swimRepeatDistance(meters: 50), to: .swimming)

        #expect(next.swimTotalMeters.truncatingRemainder(dividingBy: 50) == 0)
    }

    @Test("Rest can never be tightened below the floor for its repeat")
    func restNeverGoesBelowItsFloor() {
        var parameters = TrainingParameters()
        parameters.swimRepeatDistanceMeters = 50
        parameters.swimRestSeconds = 65

        let next = parameters.applying(.swimRestDuration(deltaSeconds: -30), to: .swimming)

        #expect(next.swimRestSeconds == 60)
    }

    @Test("A warm-up never dominates the session in a long pool")
    func warmUpScalesWithVolume() {
        var parameters = TrainingParameters()
        parameters.swimPoolLengthMeters = 50
        parameters.swimRepeatDistanceMeters = 50
        parameters.swimTotalMeters = 300

        let swim = WorkoutTemplates.techniqueSwim(on: .now, parameters: parameters)
        let warmUp = swim.orderedSteps.first { $0.kind == .warmUp }

        #expect(swim.estimatedDistanceMeters == 300)
        #expect((warmUp?.totalDistanceMeters ?? 0) <= 150)
    }
}
