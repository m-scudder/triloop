import Foundation
import Testing

@testable import TriLoop

@Suite("Starting parameters")
struct StartingParameterResolverTests {
    private let resolver = StartingParameterResolver()

    private func resolve(
        running: RunningBaseline = .none,
        swimming: SwimmingBaseline = .none,
        cycling: CyclingBaseline = .under20,
        goal: TrainingGoal = .generalFitness,
        pool: Double = 25
    ) -> TrainingParameters {
        resolver.resolve(
            baseline: AthleteBaseline(running: running, swimming: swimming, cycling: cycling),
            goal: goal,
            poolLengthMeters: pool
        )
    }

    // MARK: - Running

    @Test("An athlete who does not run starts on walk-dominant intervals")
    func nonRunnerStartsOnRunWalk() {
        let parameters = resolve(running: .none)

        #expect(parameters.runIsContinuous == false)
        #expect(parameters.runIntervalSeconds == 60)
        #expect(parameters.runWalkSeconds > parameters.runIntervalSeconds)
    }

    @Test("A run/walk athlete starts ahead of an absolute beginner")
    func runWalkAthleteStartsAhead() {
        let beginner = resolve(running: .none)
        let runWalker = resolve(running: .runWalk)

        #expect(runWalker.runIsContinuous == false)
        #expect(runWalker.runIntervalSeconds > beginner.runIntervalSeconds)
        #expect(runWalker.runWalkSeconds < beginner.runWalkSeconds)
    }

    @Test("A continuous runner is never given beginner intervals")
    func continuousRunnerSkipsIntervals() {
        for baseline in [RunningBaseline.continuous10Minutes, .continuous20To30Minutes, .regular5K] {
            let parameters = resolve(running: baseline)

            #expect(parameters.runIsContinuous)
            #expect(parameters.runContinuousSeconds >= TrainingParameters.Limits.minimumContinuousRunSeconds)
        }
    }

    @Test("A thirty minute runner starts well above a ten minute runner")
    func continuousDurationTracksAbility() {
        let ten = resolve(running: .continuous10Minutes)
        let thirty = resolve(running: .continuous20To30Minutes)
        let fiveK = resolve(running: .regular5K)

        #expect(ten.runContinuousSeconds < thirty.runContinuousSeconds)
        #expect(thirty.runContinuousSeconds < fiveK.runContinuousSeconds)
        #expect(thirty.runContinuousSeconds >= TimeInterval(15 * 60))
    }

    @Test("Starting work sits below stated ability rather than at it")
    func startsBelowStatedCeiling() {
        let parameters = resolve(running: .continuous20To30Minutes)

        // Stated 20–30 minutes; week one should not open at the top of it.
        #expect(parameters.runContinuousSeconds <= TimeInterval(25 * 60))
    }

    // MARK: - Swimming

    @Test("A 25 m swimmer gets short repeats")
    func shortSwimmerGetsShortRepeats() {
        let parameters = resolve(swimming: .continuous25, pool: 25)

        #expect(parameters.swimRepeatDistanceMeters == 25)
        #expect(parameters.swimTotalMeters >= TrainingParameters.Limits.minimumSwimMeters)
        #expect(parameters.swimTotalMeters.truncatingRemainder(dividingBy: 25) == 0)
    }

    @Test("A 100 m swimmer is not treated as an absolute beginner")
    func strongSwimmerStartsHigher() {
        let novice = resolve(swimming: .continuous25)
        let capable = resolve(swimming: .continuous100)

        #expect(capable.swimTotalMeters > novice.swimTotalMeters)
        #expect(capable.swimRestSeconds < novice.swimRestSeconds)
    }

    @Test("Repeat distance follows the pool when ability allows")
    func repeatsFollowThePool() {
        let parameters = resolve(swimming: .continuous100, pool: 50)

        #expect(parameters.swimRepeatDistanceMeters == 50)
        #expect(parameters.swimTotalMeters.truncatingRemainder(dividingBy: 50) == 0)
    }

    @Test("A long pool never forces a repeat beyond what the athlete can swim")
    func abilityBeatsPoolGeometry() {
        let parameters = resolve(swimming: .continuous25, pool: 50)

        #expect(parameters.swimRepeatDistanceMeters == 25)
    }

    // MARK: - Cycling

    @Test("A short-duration cyclist starts conservatively")
    func shortCyclistStartsLow() {
        let parameters = resolve(cycling: .under20)

        #expect(parameters.rideWorkSeconds <= TimeInterval(20 * 60))
        #expect(parameters.rideWorkSeconds >= TrainingParameters.Limits.minimumRideWorkSeconds)
    }

    @Test("An hour-long cyclist does not start at beginner duration")
    func longCyclistStartsHigher() {
        let short = resolve(cycling: .under20)
        let long = resolve(cycling: .sixtyPlus)

        #expect(long.rideWorkSeconds > short.rideWorkSeconds)
        #expect(long.rideWorkSeconds >= TimeInterval(45 * 60))
    }

    // MARK: - Goal

    @Test("Returning athletes start below their stated ability")
    func returningAthletesStartLighter() {
        let fitness = resolve(running: .regular5K, cycling: .sixtyPlus, goal: .generalFitness)
        let returning = resolve(running: .regular5K, cycling: .sixtyPlus, goal: .returnToTraining)

        #expect(returning.runContinuousSeconds < fitness.runContinuousSeconds)
        #expect(returning.rideWorkSeconds < fitness.rideWorkSeconds)
    }

    @Test("An ambitious goal never produces more work than a neutral one")
    func goalsNeverInflateStartingLoad() {
        let neutral = resolve(running: .runWalk, swimming: .continuous50, cycling: .thirtyToFortyFive)

        for goal in TrainingGoal.allCases {
            let parameters = resolve(
                running: .runWalk,
                swimming: .continuous50,
                cycling: .thirtyToFortyFive,
                goal: goal
            )

            #expect(parameters.rideWorkSeconds <= neutral.rideWorkSeconds)
            #expect(parameters.swimTotalMeters <= neutral.swimTotalMeters)
        }
    }

    @Test("Resolution is deterministic")
    func resolutionIsDeterministic() {
        let baseline = AthleteBaseline(running: .runWalk, swimming: .continuous50, cycling: .twentyToThirty)

        let first = resolver.resolve(baseline: baseline, goal: .firstTriathlon, poolLengthMeters: 25)
        let second = resolver.resolve(baseline: baseline, goal: .firstTriathlon, poolLengthMeters: 25)

        #expect(first == second)
    }
}

@Suite("Pool length")
struct PoolLengthTests {

    @Test("A pool outside the permitted range is rejected")
    func invalidLengthsAreRejected() {
        #expect(PoolLength.isValid(25))
        #expect(PoolLength.isValid(50))
        #expect(PoolLength.isValid(33.3))
        #expect(PoolLength.isValid(0) == false)
        #expect(PoolLength.isValid(-25) == false)
        #expect(PoolLength.isValid(500) == false)
    }

    @Test("An out-of-range value clamps rather than producing an unusable pool")
    func lengthsClamp() {
        #expect(PoolLength(meters: 0).meters == PoolLength.permittedRange.lowerBound)
        #expect(PoolLength(meters: 1000).meters == PoolLength.permittedRange.upperBound)
    }

    @Test("Volume rounds to whole repeats")
    func volumeRoundsToRepeats() {
        let pool = PoolLength.olympic

        #expect(pool.roundedVolume(320, repeatDistance: 50) == 300)
        #expect(pool.roundedVolume(10, repeatDistance: 50) == 50)
        #expect(pool.repeats(of: 300, repeatDistance: 50) == 6)
        #expect(PoolLength.short.repeats(of: 300, repeatDistance: 25) == 12)
    }

    @Test("Whole lengths are only possible once ability reaches the wall")
    func wholeLengthsNeedAbility() {
        #expect(PoolLength.olympic.supportsWholeLengths(for: .continuous25) == false)
        #expect(PoolLength.olympic.supportsWholeLengths(for: .continuous50))
        #expect(PoolLength.short.supportsWholeLengths(for: .continuous25))
        #expect(PoolLength.short.supportsWholeLengths(for: .none) == false)
    }
}
