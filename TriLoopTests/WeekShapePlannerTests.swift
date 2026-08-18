import Foundation
import Testing

@testable import TriLoop

@Suite("Week shape planning")
struct WeekShapePlannerTests {
    private let planner = WeekShapePlanner()

    private func schedule(_ available: Set<Weekday>, minutes: [Weekday: Int] = [:]) -> AthleteSchedule {
        AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(
                    weekday: $0,
                    isAvailable: available.contains($0),
                    maxDurationMinutes: minutes[$0]
                )
            }
        )
    }

    private var everyDay: AthleteSchedule { .everyDay() }

    private func preferences(run: Int = 0, swim: Int = 0, cycle: Int = 0, minutes: Int = 45) -> [SportPreference] {
        [
            SportPreference(sport: .running, sessionsPerWeek: run, typicalMinutes: minutes),
            SportPreference(sport: .swimming, sessionsPerWeek: swim, typicalMinutes: minutes),
            SportPreference(sport: .cycling, sessionsPerWeek: cycle, typicalMinutes: minutes)
        ]
    }

    private func days(_ shape: WeekShape, of discipline: Discipline) -> [Int] {
        shape.disciplines.enumerated().compactMap { $0.element == discipline ? $0.offset : nil }
    }

    @Test("Nothing is scheduled on a rest day")
    func restDaysStayEmpty() {
        let plan = schedule([.monday, .wednesday, .friday])

        let shape = planner.plan(
            schedule: plan,
            frequencies: WeekShapePlanner.frequencies(from: preferences(run: 2, swim: 2), schedule: plan)
        )

        for (offset, discipline) in shape.disciplines.enumerated() where discipline.isTrainingSession {
            #expect(plan.isAvailable(on: Weekday.trainingWeek[offset]))
        }
    }

    @Test("A day shorter than the session is not used for it")
    func durationLimitsAreRespected() {
        let plan = schedule(Set(Weekday.trainingWeek), minutes: [.wednesday: 20])

        let shape = planner.plan(
            schedule: plan,
            frequencies: [SportFrequency(sport: .cycling, sessions: 3)],
            durations: [.cycling: TimeInterval(60 * 60)]
        )

        #expect(shape.disciplines[Weekday.wednesday.offsetFromMonday] == .rest)
    }

    @Test("Available days are not filled just because they exist")
    func availableDaysAreNotAllFilled() {
        let shape = planner.plan(
            schedule: everyDay,
            frequencies: WeekShapePlanner.frequencies(from: preferences(run: 2, swim: 2, cycle: 2), schedule: everyDay)
        )

        #expect(shape.disciplines.filter(\.isTrainingSession).count == 6)
        #expect(shape.disciplines.contains(.rest))
    }

    @Test("Runs are spaced rather than stacked on consecutive days")
    func runsAreSpaced() {
        let shape = planner.plan(
            schedule: everyDay,
            frequencies: [SportFrequency(sport: .running, sessions: 2)]
        )

        let runDays = days(shape, of: .running)
        #expect(runDays.count == 2)
        #expect(abs(runDays[0] - runDays[1]) >= 2)
    }

    @Test("The longest session claims a day before a shorter one takes it")
    func longestSessionIsPlacedFirst() {
        // Only Saturday is long enough for the ride.
        let limits = Weekday.trainingWeek.reduce(into: [Weekday: Int]()) { limits, day in
            limits[day] = day == .saturday ? 120 : 40
        }
        let plan = schedule(Set(Weekday.trainingWeek), minutes: limits)

        let shape = planner.plan(
            schedule: plan,
            frequencies: [
                SportFrequency(sport: .running, sessions: 2),
                SportFrequency(sport: .cycling, sessions: 1)
            ],
            durations: [.running: TimeInterval(30 * 60), .cycling: TimeInterval(90 * 60)]
        )

        #expect(shape.disciplines[Weekday.saturday.offsetFromMonday] == .cycling)
        #expect(shape.fittedEverything)
    }

    @Test("An unusual schedule still produces a valid week")
    func oddScheduleStillWorks() {
        let plan = schedule([.wednesday, .saturday, .sunday])

        let shape = planner.plan(
            schedule: plan,
            frequencies: WeekShapePlanner.frequencies(from: preferences(run: 1, swim: 1, cycle: 1), schedule: plan)
        )

        #expect(shape.isViable)
        #expect(shape.disciplines.count == 7)
        #expect(shape.disciplines[Weekday.monday.offsetFromMonday] == .rest)
        #expect(shape.fittedEverything)
    }

    @Test("More sessions than days is reported rather than silently dropped")
    func impossibleScheduleIsExplicit() {
        let plan = schedule([.monday, .tuesday])

        let shape = planner.plan(
            schedule: plan,
            frequencies: [SportFrequency(sport: .running, sessions: 3)]
        )

        #expect(shape.isViable)
        #expect(shape.fittedEverything == false)
        #expect(shape.unplaced[.running] == 1)
    }

    @Test("A schedule with no days produces an unviable week rather than a crash")
    func emptyScheduleIsUnviable() {
        let shape = planner.plan(
            schedule: .empty,
            frequencies: WeekShapePlanner.frequencies(from: preferences(run: 2), schedule: .empty)
        )

        #expect(shape.isViable == false)
        #expect(shape.disciplines.allSatisfy { $0 == .rest })
    }

    @Test("Planning is deterministic")
    func planningIsDeterministic() {
        let frequencies = WeekShapePlanner.frequencies(
            from: preferences(run: 2, swim: 2, cycle: 2),
            schedule: everyDay
        )

        let first = planner.plan(schedule: everyDay, frequencies: frequencies)
        let second = planner.plan(schedule: everyDay, frequencies: frequencies)

        #expect(first == second)
    }

    @Test("Stated frequency is capped by the days available")
    func frequencyIsCappedByDays() {
        let plan = schedule([.tuesday, .thursday])

        let frequencies = WeekShapePlanner.frequencies(
            from: preferences(run: 3, swim: 2),
            schedule: plan
        )

        #expect(frequencies.first { $0.sport == .running }?.sessions == 2)
        #expect(frequencies.first { $0.sport == .swimming }?.sessions == 2)
        #expect(frequencies.contains { $0.sport == .cycling } == false)
    }

    @Test("A sport the athlete does not want is never scheduled")
    func untrainedSportIsAbsent() {
        let frequencies = WeekShapePlanner.frequencies(
            from: preferences(run: 2, swim: 0, cycle: 1),
            schedule: everyDay
        )

        let shape = planner.plan(schedule: everyDay, frequencies: frequencies)

        #expect(shape.disciplines.contains(.swimming) == false)
        #expect(shape.disciplines.contains(.running))
        #expect(shape.disciplines.contains(.cycling))
    }
}
