import Foundation
import Testing

@testable import TriLoop

@Suite("Week shape planning")
struct WeekShapePlannerTests {
    private let planner = WeekShapePlanner()

    private func schedule(
        _ days: [(Weekday, Set<Sport>, Int?)]
    ) -> AthleteSchedule {
        AthleteSchedule(
            days: days.map {
                TrainingAvailability(weekday: $0.0, sports: $0.1, maxDurationMinutes: $0.2)
            }
        )
    }

    private func everyDay(_ sports: Set<Sport>, minutes: Int? = nil) -> AthleteSchedule {
        AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(weekday: $0, sports: sports, maxDurationMinutes: minutes)
            }
        )
    }

    private func days(_ shape: WeekShape, of discipline: Discipline) -> [Int] {
        shape.disciplines.enumerated().compactMap { $0.element == discipline ? $0.offset : nil }
    }

    @Test("A sport is never scheduled on a day it is not allowed")
    func unavailableSportIsNeverScheduled() {
        let plan = schedule([
            (.monday, [.running], nil),
            (.tuesday, [.swimming], nil),
            (.wednesday, [.running], nil),
            (.thursday, [.swimming], nil),
            (.friday, [.cycling], nil),
            (.saturday, [.cycling], nil),
            (.sunday, [], nil)
        ])

        let shape = planner.plan(
            schedule: plan,
            frequencies: WeekShapePlanner.defaultFrequencies(for: plan)
        )

        for (offset, discipline) in shape.disciplines.enumerated() {
            guard let sport = discipline.sport else { continue }
            let weekday = Weekday.trainingWeek[offset]
            #expect(plan.allows(sport, on: weekday))
        }
    }

    @Test("A day shorter than the session is not used for it")
    func durationLimitsAreRespected() {
        let plan = everyDay([.running, .cycling])
        let limited = AthleteSchedule(
            days: plan.days.map { day in
                var updated = day
                updated.maxDurationMinutes = day.weekday == .wednesday ? 20 : 90
                return updated
            }
        )

        let shape = planner.plan(
            schedule: limited,
            frequencies: [SportFrequency(sport: .cycling, sessions: 3)],
            durations: [.cycling: TimeInterval(60 * 60)]
        )

        #expect(shape.disciplines[Weekday.wednesday.offsetFromMonday] == .rest)
    }

    @Test("Available days are not filled just because they exist")
    func availableDaysAreNotAllFilled() {
        let plan = everyDay([.running, .swimming, .cycling])

        let shape = planner.plan(
            schedule: plan,
            frequencies: WeekShapePlanner.defaultFrequencies(for: plan)
        )

        let training = shape.disciplines.filter(\.isTrainingSession).count
        #expect(training == 6)
        #expect(shape.disciplines.contains(.rest))
    }

    @Test("Runs are spaced rather than stacked on consecutive days")
    func runsAreSpaced() {
        let plan = everyDay([.running, .swimming, .cycling])

        let shape = planner.plan(
            schedule: plan,
            frequencies: [SportFrequency(sport: .running, sessions: 2)]
        )

        let runDays = days(shape, of: .running)
        #expect(runDays.count == 2)
        #expect(abs(runDays[0] - runDays[1]) >= 2)
    }

    @Test("A scarce sport claims its only day before a flexible one takes it")
    func scarceSportsAreScheduledFirst() {
        let plan = schedule([
            (.monday, [.running, .swimming], nil),
            (.tuesday, [.running], nil),
            (.wednesday, [.running], nil),
            (.thursday, [.running], nil),
            (.friday, [.running], nil),
            (.saturday, [.running], nil),
            (.sunday, [], nil)
        ])

        let shape = planner.plan(
            schedule: plan,
            frequencies: [
                SportFrequency(sport: .running, sessions: 2),
                SportFrequency(sport: .swimming, sessions: 1)
            ]
        )

        #expect(shape.disciplines[Weekday.monday.offsetFromMonday] == .swimming)
        #expect(shape.fittedEverything)
    }

    @Test("An unusual schedule still produces a valid week")
    func oddScheduleStillWorks() {
        let plan = schedule([
            (.monday, [], nil),
            (.tuesday, [], nil),
            (.wednesday, [.swimming], 45),
            (.thursday, [], nil),
            (.friday, [], nil),
            (.saturday, [.running, .cycling], 120),
            (.sunday, [.cycling], 60)
        ])

        let shape = planner.plan(
            schedule: plan,
            frequencies: WeekShapePlanner.defaultFrequencies(for: plan)
        )

        #expect(shape.isViable)
        #expect(shape.disciplines.count == 7)
        #expect(shape.disciplines[Weekday.monday.offsetFromMonday] == .rest)
        #expect(shape.disciplines[Weekday.wednesday.offsetFromMonday] == .swimming)
    }

    @Test("More sessions than days is reported rather than silently dropped")
    func impossibleScheduleIsExplicit() {
        let plan = schedule([
            (.monday, [.running], nil),
            (.tuesday, [], nil),
            (.wednesday, [], nil),
            (.thursday, [], nil),
            (.friday, [], nil),
            (.saturday, [], nil),
            (.sunday, [], nil)
        ])

        let shape = planner.plan(
            schedule: plan,
            frequencies: [SportFrequency(sport: .running, sessions: 3)]
        )

        #expect(shape.isViable)
        #expect(shape.fittedEverything == false)
        #expect(shape.unplaced[.running] == 2)
    }

    @Test("A schedule allowing nothing produces an unviable week rather than a crash")
    func emptyScheduleIsUnviable() {
        let shape = planner.plan(
            schedule: .empty,
            frequencies: WeekShapePlanner.defaultFrequencies(for: .empty)
        )

        #expect(shape.isViable == false)
        #expect(shape.disciplines.allSatisfy { $0 == .rest })
    }

    @Test("Planning is deterministic")
    func planningIsDeterministic() {
        let plan = everyDay([.running, .swimming, .cycling])
        let frequencies = WeekShapePlanner.defaultFrequencies(for: plan)

        let first = planner.plan(schedule: plan, frequencies: frequencies)
        let second = planner.plan(schedule: plan, frequencies: frequencies)

        #expect(first == second)
    }

    @Test("Frequency is capped by how many days allow the sport")
    func frequencyIsCappedByAvailability() {
        let plan = schedule([
            (.monday, [.running, .swimming], nil),
            (.tuesday, [.running], nil),
            (.wednesday, [.running], nil),
            (.thursday, [.running], nil),
            (.friday, [.running], nil),
            (.saturday, [.running], nil),
            (.sunday, [], nil)
        ])

        let frequencies = WeekShapePlanner.defaultFrequencies(for: plan)

        #expect(frequencies.first { $0.sport == .swimming }?.sessions == 1)
        #expect(frequencies.first { $0.sport == .running }?.sessions == 2)
        #expect(frequencies.contains { $0.sport == .cycling } == false)
    }
}
