#if DEBUG
import Foundation
import Testing
@testable import TriLoop

@Suite("Historical metric coverage")
struct HistoricalMetricCoverageTests {

    private func record(
        sport: Sport?,
        name: String = "Activity",
        heartRate: Double? = 140,
        energy: Double? = 300,
        distance: Double? = 5_000,
        lengths: Int? = nil,
        metrics: RecordedMetrics = RecordedMetrics()
    ) -> HealthWorkoutRecord {
        HealthWorkoutRecord(
            id: UUID(),
            activityName: name,
            sport: sport,
            start: Date(timeIntervalSince1970: 1_760_000_000),
            end: Date(timeIntervalSince1970: 1_760_003_600),
            duration: 3_600,
            distanceMeters: distance,
            averageHeartRate: heartRate,
            energyKilocalories: energy,
            swimmingLengths: lengths,
            metrics: metrics,
            sourceName: "Test"
        )
    }

    private func entry(_ report: [MetricCoverage], _ name: String) throws -> MetricCoverage {
        try #require(report.first { $0.name == name })
    }

    @Test("Cycling power is not counted as missing on runs")
    func cyclingPowerIsNotApplicableToRuns() throws {
        let report = HistoricalMetricCoverage.report(for: [
            record(sport: .running),
            record(sport: .running)
        ])

        // The trap this guards: counting 0/2 would make every runner's report
        // look like ingestion is broken.
        let power = try entry(report, "Cycling Power")
        #expect(power.applicable == 0)
        #expect(power.summary == "Not applicable")
        #expect(!power.isEntirelyAbsent)
    }

    @Test("A metric applicable but never recorded is flagged")
    func applicableButAbsentIsFlagged() throws {
        let report = HistoricalMetricCoverage.report(for: [
            record(sport: .running),
            record(sport: .running)
        ])

        let runningPower = try entry(report, "Running Power")
        #expect(runningPower.applicable == 2)
        #expect(runningPower.available == 0)
        #expect(runningPower.isEntirelyAbsent)
        #expect(runningPower.summary == "0 / 2")
    }

    @Test("Partial coverage is reported as a fraction")
    func partialCoverage() throws {
        let report = HistoricalMetricCoverage.report(for: [
            record(sport: .running, metrics: RecordedMetrics(averageRunningPower: 240)),
            record(sport: .running),
            record(sport: .running, metrics: RecordedMetrics(averageRunningPower: 250))
        ])

        #expect(try entry(report, "Running Power").summary == "2 / 3")
    }

    @Test("Heart rate applies to every activity, trained or not")
    func heartRateAppliesToEverything() throws {
        let report = HistoricalMetricCoverage.report(for: [
            record(sport: .running),
            record(sport: nil, name: "Functional Strength Training"),
            record(sport: nil, name: "Yoga", heartRate: nil)
        ])

        let heartRate = try entry(report, "Heart Rate")
        #expect(heartRate.applicable == 3)
        #expect(heartRate.available == 2)
    }

    @Test("Effort prefers the athlete's rating but counts either")
    func effortCountsEitherSource() throws {
        let report = HistoricalMetricCoverage.report(for: [
            record(sport: nil, metrics: RecordedMetrics(workoutEffort: 6)),
            record(sport: nil, metrics: RecordedMetrics(estimatedWorkoutEffort: 4)),
            record(sport: nil)
        ])

        #expect(try entry(report, "Workout Effort").summary == "2 / 3")
    }

    @Test("An empty history reports nothing as applicable")
    func emptyHistory() throws {
        let report = HistoricalMetricCoverage.report(for: [])
        #expect(report.allSatisfy { $0.applicable == 0 })
        #expect(report.allSatisfy { !$0.isEntirelyAbsent })
    }
}

@Suite("Per-workout metric presence")
struct MetricPresenceTests {

    private func record(sport: Sport?, metrics: RecordedMetrics = RecordedMetrics()) -> HealthWorkoutRecord {
        HealthWorkoutRecord(
            id: UUID(),
            activityName: "Activity",
            sport: sport,
            start: .now,
            end: .now,
            duration: 1_800,
            distanceMeters: nil,
            averageHeartRate: 140,
            energyKilocalories: nil,
            swimmingLengths: nil,
            metrics: metrics,
            sourceName: nil
        )
    }

    @Test("A swim is never shown as missing cycling power")
    func swimHasNoCyclingRows() {
        let names = record(sport: .swimming).metricPresence.map(\.name)
        #expect(!names.contains("Cycling Power"))
        #expect(!names.contains("Running Power"))
        #expect(names.contains("Swim Lengths"))
    }

    @Test("An untrained activity lists only universal metrics")
    func untrainedActivityIsUniversalOnly() {
        let names = record(sport: nil).metricPresence.map(\.name)
        #expect(names == ["Heart Rate", "Active Energy", "Workout Effort"])
    }

    @Test("Presence reflects what was actually recorded")
    func presenceReflectsRecording() throws {
        let entries = record(
            sport: .running,
            metrics: RecordedMetrics(averageRunningSpeed: 3.0)
        ).metricPresence

        let speed = try #require(entries.first { $0.name == "Running Speed" })
        let power = try #require(entries.first { $0.name == "Running Power" })
        #expect(speed.isPresent)
        #expect(!power.isPresent)
    }
}
#endif
