import Foundation
import Testing

@testable import Athevia

@Suite("Training parameters")
struct TrainingParametersTests {

    @Test("Week one defaults match the seeded week")
    func defaultsMatchWeekOne() {
        let parameters = TrainingParameters()

        #expect(parameters.runIntervalSeconds == 60)
        #expect(parameters.runRepeatCount == 6)
        #expect(parameters.swimTotalMeters == 300)
        #expect(parameters.swimRestSeconds == 45)
        #expect(parameters.rideWorkSeconds == TimeInterval(20 * 60))
    }

    @Test("Progression moves only its own variable")
    func progressionIsSingleVariable() {
        let base = TrainingParameters()
        let next = base.applying(.runIntervalDuration(deltaSeconds: 15), to: .running)

        #expect(next.runIntervalSeconds == 75)
        #expect(next.runRepeatCount == base.runRepeatCount)
        #expect(next.runWalkSeconds == base.runWalkSeconds)
        #expect(next.rideWorkSeconds == base.rideWorkSeconds)
        #expect(next.swimTotalMeters == base.swimTotalMeters)
    }

    @Test("Holding changes nothing")
    func holdIsANoOp() {
        let base = TrainingParameters()

        #expect(base.applying(.hold, to: .running) == base)
        #expect(base.applying(.substituteRecovery, to: .cycling) == base)
    }

    @Test("Each sport reduces volume with its own variable")
    func reductionUsesTheRightVariable() {
        let base = TrainingParameters()

        let run = base.applying(.reduceVolume(fraction: 0.2), to: .running)
        let swim = base.applying(.reduceVolume(fraction: 0.2), to: .swimming)
        let ride = base.applying(.reduceVolume(fraction: 0.2), to: .cycling)

        #expect(run.runRepeatCount == 5)
        #expect(run.runIntervalSeconds == base.runIntervalSeconds)
        #expect(swim.swimTotalMeters == 250)
        #expect(ride.rideWorkSeconds == TimeInterval(15 * 60))
    }

    @Test("Swim volume stays in whole lengths")
    func swimVolumeRoundsToLengths() {
        let parameters = TrainingParameters().applying(.reduceVolume(fraction: 0.1), to: .swimming)

        #expect(parameters.swimTotalMeters.truncatingRemainder(dividingBy: 25) == 0)
    }

    @Test("Repeated reductions stop at a floor")
    func reductionsRespectFloors() {
        var parameters = TrainingParameters()
        for _ in 0..<20 {
            parameters = parameters.applying(.reduceVolume(fraction: 0.5), to: .running)
            parameters = parameters.applying(.reduceVolume(fraction: 0.5), to: .swimming)
            parameters = parameters.applying(.reduceVolume(fraction: 0.5), to: .cycling)
        }

        #expect(parameters.runRepeatCount == TrainingParameters.Limits.minimumRunRepeatCount)
        #expect(parameters.swimTotalMeters == TrainingParameters.Limits.minimumSwimMeters)
        #expect(parameters.rideWorkSeconds == TrainingParameters.Limits.minimumRideWorkSeconds)
    }

    @Test("A larger availability window never manufactures extra cycling load")
    func largerWindowDoesNotInflateCycling() {
        let parameters = TrainingParameters().fillingTrainingWindow(minutes: 60)
        #expect(parameters.rideWorkSeconds == 20 * 60)
        #expect(
            parameters.rideWarmUpSeconds
                + parameters.rideWorkSeconds
                + parameters.rideCooldownSeconds == 30 * 60
        )
    }

    @Test("Training window cap never exceeds selected time")
    func cappedWindowStaysInsideAvailability() {
        let parameters = TrainingParameters().fillingTrainingWindow(minutes: 30)
        #expect(
            parameters.rideWarmUpSeconds
                + parameters.rideWorkSeconds
                + parameters.rideCooldownSeconds <= 30 * 60
        )
    }


    @Test("Continuous endurance durations normalize to five minute blocks")
    func enduranceDurationsUseFiveMinuteBlocks() {
        var parameters = TrainingParameters()
        parameters.runIsContinuous = true
        parameters.runContinuousSeconds = 30 * 60

        let taperedRun = parameters.applying(.reduceVolume(fraction: 0.2), to: .running)
        let taperedRide = parameters.applying(.reduceVolume(fraction: 0.2), to: .cycling)

        #expect(taperedRun.runContinuousSeconds == 20 * 60)
        #expect(taperedRide.rideWorkSeconds == 15 * 60)
        #expect(taperedRun.runContinuousSeconds.truncatingRemainder(dividingBy: 5 * 60) == 0)
        #expect(taperedRide.rideWorkSeconds.truncatingRemainder(dividingBy: 5 * 60) == 0)
    }

}
