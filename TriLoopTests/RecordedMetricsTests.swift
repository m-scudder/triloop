import Foundation
import Testing
@testable import TriLoop

@Suite("Recorded metrics ingestion")
struct RecordedMetricsTests {

    @Test("Nothing recorded reads as empty rather than zero")
    func emptyMetrics() {
        let metrics = RecordedMetrics()
        #expect(metrics.isEmpty)
        #expect(metrics.averageCyclingPower == nil)
        #expect(metrics.appleEffort == nil)
    }

    @Test("A single reading makes the bag non-empty")
    func oneReadingIsNotEmpty() {
        #expect(!RecordedMetrics(averageRunningPower: 240).isEmpty)
    }

    @Test("A record written before these fields existed still decodes")
    func decodesOlderRecord() throws {
        // Exactly what an earlier build wrote: cadence and nothing else.
        let json = Data(#"{"averageCadence":168}"#.utf8)
        let metrics = try JSONDecoder().decode(RecordedMetrics.self, from: json)

        #expect(metrics.averageCadence == 168)
        #expect(metrics.averageRunningPower == nil)
        #expect(!metrics.isEmpty)
    }

    @Test("An empty record decodes rather than throwing")
    func decodesEmptyRecord() throws {
        let metrics = try JSONDecoder().decode(RecordedMetrics.self, from: Data("{}".utf8))
        #expect(metrics.isEmpty)
    }

    @Test("Every field survives a round trip")
    func roundTrip() throws {
        let original = RecordedMetrics(
            averageCadence: 170,
            averageRunningSpeed: 3.1,
            averageRunningPower: 250,
            averageStrideLength: 1.1,
            averageGroundContactTime: 240,
            averageVerticalOscillation: 8.2,
            averageCyclingSpeed: 7.4,
            averageCyclingCadence: 88,
            averageCyclingPower: 190,
            functionalThresholdPower: 230,
            workoutEffort: 6,
            estimatedWorkoutEffort: 5
        )

        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(RecordedMetrics.self, from: data) == original)
    }

    @Test("The athlete's own effort rating wins over Apple's estimate")
    func ratedEffortWins() {
        #expect(RecordedMetrics(workoutEffort: 7, estimatedWorkoutEffort: 4).appleEffort == 7)
        #expect(RecordedMetrics(estimatedWorkoutEffort: 4).appleEffort == 4)
    }
}

@Suite("Fixture sensor coverage")
struct FixtureMetricCoverageTests {

    private func workouts(_ dataset: SimulationDataset, sport: Sport) -> [ImportedWorkout] {
        let reference = Date(timeIntervalSince1970: 1_760_000_000)
        return SimulationFixture.generate(dataset, asOf: reference)
            .workouts
            .filter { $0.sport == sport }
    }

    @Test("A cyclist with a power meter reports watts")
    func powerCyclistHasWatts() throws {
        let ride = try #require(workouts(.powerCyclist, sport: .cycling).first)
        #expect(ride.metrics.averageCyclingPower != nil)
        #expect(ride.metrics.averageCyclingCadence != nil)
    }

    @Test("The missing-power fixture reports no watts at all")
    func missingPowerHasNoWatts() throws {
        let rides = workouts(.missingPower, sport: .cycling)
        #expect(!rides.isEmpty)
        // §59: the no-power path is only tested if the fixture truly has none.
        #expect(rides.allSatisfy { $0.metrics.averageCyclingPower == nil })
        #expect(rides.allSatisfy { $0.metrics.functionalThresholdPower == nil })
        // Speed and cadence do not need a power meter, so they remain.
        #expect(rides.allSatisfy { $0.metrics.averageCyclingSpeed != nil })
    }

    @Test("Running dynamics appear only on experienced fixtures")
    func runningDynamicsAreGated() throws {
        let experienced = try #require(workouts(.experiencedRunner, sport: .running).first)
        #expect(experienced.metrics.averageRunningPower != nil)
        #expect(experienced.metrics.averageStrideLength != nil)

        let beginner = try #require(workouts(.beginnerTwelveWeeks, sport: .running).first)
        #expect(beginner.metrics.averageRunningPower == nil)
        #expect(beginner.metrics.averageVerticalOscillation == nil)
        // Cadence and speed come from any watch, so a beginner still has them.
        #expect(beginner.metrics.averageCadence != nil)
        #expect(beginner.metrics.averageRunningSpeed != nil)
    }

    @Test("Fixtures without effort scores force the RPE fallback")
    func effortScoreIsGated() throws {
        let missing = workouts(.missingHeartRate, sport: .running)
        #expect(!missing.isEmpty)
        #expect(missing.allSatisfy { $0.metrics.appleEffort == nil })

        let triathlete = try #require(workouts(.experiencedTriathlete, sport: .running).first)
        #expect(triathlete.metrics.appleEffort != nil)
    }

    @Test("Swimming carries no land sensor readings")
    func swimmingHasNoLandMetrics() throws {
        let swim = try #require(workouts(.beginnerTwelveWeeks, sport: .swimming).first)
        #expect(swim.metrics.averageRunningSpeed == nil)
        #expect(swim.metrics.averageCyclingCadence == nil)
    }
}
