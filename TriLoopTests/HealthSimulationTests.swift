import Foundation
import Testing
@testable import TriLoop

/// Phase 9 §6/§7: the simulation must be reproducible and must not leak.
///
/// Determinism is the load-bearing property. If a fixture drifts between runs,
/// every downstream intelligence test becomes flaky and every bug report
/// becomes unreproducible, so it is asserted directly rather than assumed.
@Suite("Health data simulation")
struct HealthSimulationTests {

    private let reference = Date(timeIntervalSince1970: 1_767_225_600) // 1 Jan 2026
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("The same dataset and date produce identical data")
    func generationIsDeterministic() {
        for dataset in SimulationDataset.allCases {
            let first = SimulationFixture.generate(dataset, asOf: reference, calendar: calendar)
            let second = SimulationFixture.generate(dataset, asOf: reference, calendar: calendar)

            #expect(first.workouts == second.workouts, "\(dataset.rawValue) workouts drifted")
            #expect(first.dailySteps == second.dailySteps, "\(dataset.rawValue) steps drifted")
            #expect(first.hourlySteps == second.hourlySteps, "\(dataset.rawValue) hourly steps drifted")
        }
    }

    @Test("Workout identifiers are stable, so re-import is a duplicate")
    func identifiersAreStable() {
        let first = SimulationFixture.generate(.beginnerFourWeeks, asOf: reference, calendar: calendar)
        let second = SimulationFixture.generate(.beginnerFourWeeks, asOf: reference, calendar: calendar)

        #expect(first.workouts.map(\.healthKitUUID) == second.workouts.map(\.healthKitUUID))
        #expect(Set(first.workouts.map(\.healthKitUUID)).count == first.workouts.count)
    }

    @Test("Different datasets differ")
    func datasetsAreDistinct() {
        let beginner = SimulationFixture.generate(.beginnerTwelveWeeks, asOf: reference, calendar: calendar)
        let advanced = SimulationFixture.generate(.experiencedTriathlete, asOf: reference, calendar: calendar)

        #expect(beginner.workouts != advanced.workouts)
    }

    @Test("No Data really is empty")
    func noDataIsEmpty() {
        let data = SimulationFixture.generate(.noData, asOf: reference, calendar: calendar)

        #expect(data.workouts.isEmpty)
        #expect(data.dailySteps.isEmpty)
    }

    @Test("Missing heart rate omits it rather than reporting zero")
    func missingHeartRateIsAbsent() async throws {
        let data = SimulationFixture.generate(.missingHeartRate, asOf: reference, calendar: calendar)

        #expect(!data.workouts.isEmpty)
        #expect(data.workouts.allSatisfy { $0.averageHeartRate == nil })
        for workout in data.workouts {
            #expect(data.samples[workout.healthKitUUID]?.heartRate.isEmpty == true)
        }
    }

    @Test("Sparse history yields too little to trend")
    func sparseHistoryIsSparse() {
        let sparse = SimulationFixture.generate(.sparseHistory, asOf: reference, calendar: calendar)
        let full = SimulationFixture.generate(.beginnerTwelveWeeks, asOf: reference, calendar: calendar)

        #expect(sparse.workouts.count < 4)
        #expect(sparse.workouts.count < full.workouts.count)
    }

    @Test("History ends at the reference date, never in the future")
    func historyRespectsReferenceDate() {
        let data = SimulationFixture.generate(.beginnerTwelveWeeks, asOf: reference, calendar: calendar)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference))!

        #expect(data.workouts.allSatisfy { $0.startDate < endOfDay })
    }

    @Test("Twelve weeks of beginner history covers twelve weeks")
    func beginnerHistorySpansTwelveWeeks() throws {
        let data = SimulationFixture.generate(.beginnerTwelveWeeks, asOf: reference, calendar: calendar)
        let earliest = try #require(data.workouts.map(\.startDate).min())
        let weeks = calendar.dateComponents([.day], from: earliest, to: reference).day ?? 0

        #expect(weeks > 70)
        #expect(data.workouts.count > 30)
    }

    @Test("The provider filters by the requested window")
    func providerFiltersByDate() async throws {
        let provider = SimulatedHealthDataProvider(
            dataset: .beginnerTwelveWeeks,
            referenceDate: reference,
            calendar: calendar
        )
        let start = calendar.date(byAdding: .day, value: -14, to: reference)!

        let recent = try await provider.workouts(from: start, to: reference)
        let all = try await provider.workouts(from: .distantPast, to: reference)

        #expect(recent.allSatisfy { $0.startDate >= start })
        #expect(recent.count < all.count)
        #expect(recent == recent.sorted { $0.startDate > $1.startDate })
    }

    @Test("A day with no step data reports nothing, not zero")
    func missingDayIsNotZero() async throws {
        let provider = SimulatedHealthDataProvider(
            dataset: .beginnerFirstWeek,
            referenceDate: reference,
            calendar: calendar
        )
        let longAgo = calendar.date(byAdding: .year, value: -3, to: reference)!

        let activity = try await provider.dailyActivity(on: longAgo)

        #expect(activity.steps == nil)
        #expect(!activity.hasAnything)
    }

    @Test("Samples exist for every generated workout")
    func samplesMatchWorkouts() async throws {
        let provider = SimulatedHealthDataProvider(
            dataset: .experiencedTriathlete,
            referenceDate: reference,
            calendar: calendar
        )
        let workouts = try await provider.workouts(from: .distantPast, to: reference)

        for workout in workouts.prefix(10) {
            let samples = try await provider.samples(forWorkout: workout.healthKitUUID)
            #expect(!samples.isEmpty, "no samples for \(workout.sport)")
        }
    }

    @Test("Swim fixtures produce lengths with rests between sets")
    func swimLengthsHaveRests() async throws {
        let data = SimulationFixture.generate(.beginnerTwelveWeeks, asOf: reference, calendar: calendar)
        let swim = try #require(data.workouts.first { $0.sport == .swimming })
        let samples = try #require(data.samples[swim.healthKitUUID])

        #expect(!samples.swimLengths.isEmpty)
        #expect(samples.swimLengths.contains { $0.followedRest })
        #expect(samples.swimLengths.allSatisfy { $0.meters == 25 })
    }

    @Test("The deterministic generator repeats for a given seed")
    func generatorRepeats() {
        var first = DeterministicGenerator(seed: 42)
        var second = DeterministicGenerator(seed: 42)
        var other = DeterministicGenerator(seed: 43)

        let a = (0..<20).map { _ in first.value(in: 0.0...1.0) }
        let b = (0..<20).map { _ in second.value(in: 0.0...1.0) }
        let c = (0..<20).map { _ in other.value(in: 0.0...1.0) }

        #expect(a == b)
        #expect(a != c)
    }

    @Test("A zero seed still produces varying values")
    func zeroSeedIsHandled() {
        var generator = DeterministicGenerator(seed: 0)
        let values = (0..<10).map { _ in generator.value(in: 0.0...1.0) }

        #expect(Set(values).count > 1)
    }

    @Test("History reads back every workout in the range, newest first")
    func historyIsOrderedAndBounded() async throws {
        let reference = Date(timeIntervalSince1970: 1_787_000_000)
        let provider = SimulatedHealthDataProvider(
            dataset: .beginnerFourWeeks,
            referenceDate: reference
        )
        let start = Calendar.current.date(byAdding: .day, value: -28, to: reference)!

        let records = try await provider.workoutHistory(from: start, to: reference)

        #expect(!records.isEmpty)
        #expect(records == records.sorted { $0.start > $1.start })
        #expect(records.allSatisfy { $0.start >= start && $0.start <= reference })
    }

    @Test("A history record carries what the fixture recorded")
    func historyRecordsCarryDetail() async throws {
        let reference = Date(timeIntervalSince1970: 1_787_000_000)
        let provider = SimulatedHealthDataProvider(
            dataset: .beginnerTwelveWeeks,
            referenceDate: reference
        )
        let start = Calendar.current.date(byAdding: .day, value: -84, to: reference)!

        let records = try await provider.workoutHistory(from: start, to: reference)
        let swim = try #require(records.first { $0.sport == .swimming })

        #expect(swim.isTrainedByTriLoop)
        #expect(swim.energyKilocalories ?? 0 > 0)
        #expect(swim.swimmingLengths ?? 0 > 0)
        #expect(swim.sourceName == "Simulated")
    }

    @Test("A history read outside the fixture's span returns nothing, not zeroes")
    func historyOutsideRangeIsEmpty() async throws {
        let reference = Date(timeIntervalSince1970: 1_787_000_000)
        let provider = SimulatedHealthDataProvider(
            dataset: .beginnerFourWeeks,
            referenceDate: reference
        )
        let future = Calendar.current.date(byAdding: .day, value: 30, to: reference)!
        let later = Calendar.current.date(byAdding: .day, value: 60, to: reference)!

        #expect(try await provider.workoutHistory(from: future, to: later).isEmpty)
    }
}
