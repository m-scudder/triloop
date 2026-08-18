import Foundation
import Testing

@testable import TriLoop

@Suite("First week")
struct FirstWeekBuilderTests {
    private let builder = FirstWeekBuilder()

    /// Monday 24 August 2026. Fixed so week length does not depend on the day
    /// the suite happens to run.
    private func monday() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)) ?? .now
    }

    private func setup(
        goal: TrainingGoal = .generalFitness,
        running: RunningBaseline = .runWalk,
        swimming: SwimmingBaseline = .continuous25,
        cycling: CyclingBaseline = .twentyToThirty,
        schedule: AthleteSchedule = .everyDay(),
        preferences: [SportPreference]? = nil
    ) -> AthleteSetup {
        AthleteSetup(
            goal: goal,
            baseline: AthleteBaseline(running: running, swimming: swimming, cycling: cycling),
            schedule: schedule,
            preferences: preferences ?? [
                SportPreference(sport: .running, sessionsPerWeek: 2, typicalMinutes: 45),
                SportPreference(sport: .swimming, sessionsPerWeek: 2, typicalMinutes: 45),
                SportPreference(sport: .cycling, sessionsPerWeek: 2, typicalMinutes: 45)
            ],
            stage: .complete,
            completedAt: .now
        )
    }

    @Test("The first week is built from the assessment, not a seed")
    func firstWeekComesFromTheAssessment() throws {
        let plan = try builder.build(setup: setup(), poolLengthMeters: 25, startDate: monday())

        #expect(plan.weekNumber == 1)
        #expect(plan.generationReasonCode == .initialAssessment)
        #expect(plan.orderedWorkouts.count == 7)
        #expect(plan.trainingSessions.isEmpty == false)
        #expect(plan.generationReason.isEmpty == false)
    }

    @Test("Parameters come from the resolver rather than defaults")
    func parametersFollowTheBaseline() throws {
        let plan = try builder.build(
            setup: setup(running: .regular5K, cycling: .sixtyPlus),
            poolLengthMeters: 25
        )

        #expect(plan.parameters.runIsContinuous)
        #expect(plan.parameters.rideWorkSeconds >= TimeInterval(45 * 60))
    }

    @Test("Starting mid-week still gives a full Monday to Sunday plan")
    func midWeekStartCoversTheWholeWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var builder = FirstWeekBuilder()
        builder.calendar = calendar

        // Thursday 20 August 2026.
        let thursday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let plan = try builder.build(setup: setup(), poolLengthMeters: 25, startDate: thursday)

        #expect(Weekday(date: plan.startDate, calendar: calendar) == .monday)
        #expect(Weekday(date: plan.endDate, calendar: calendar) == .sunday)
        #expect(plan.orderedWorkouts.count == 7)

        // Nothing to do on the days that had already gone.
        let elapsed = plan.orderedWorkouts.filter { $0.date < thursday }
        #expect(elapsed.count == 3)
        #expect(elapsed.allSatisfy { $0.discipline == .rest })
        #expect(plan.trainingSessions.allSatisfy { $0.date >= thursday })
    }

    @Test("Sessions asked for are packed into the days that remain")
    func sessionsFitTheRemainingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var builder = FirstWeekBuilder()
        builder.calendar = calendar

        let thursday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))
        let plan = try builder.build(
            setup: setup(preferences: [
                SportPreference(sport: .running, sessionsPerWeek: 2, typicalMinutes: 30),
                SportPreference(sport: .swimming, sessionsPerWeek: 1, typicalMinutes: 45)
            ]),
            poolLengthMeters: 25,
            startDate: thursday
        )

        #expect(plan.trainingSessions.count == 3)
        #expect(plan.trainingSessions.allSatisfy { $0.date >= thursday })
    }

    @Test("A short week still places sessions only on training days")
    func shortWeekRespectsTrainingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var builder = FirstWeekBuilder()
        builder.calendar = calendar

        let schedule = AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(weekday: $0, isAvailable: $0 != .sunday)
            }
        )

        let friday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 21)))
        let plan = try builder.build(
            setup: setup(schedule: schedule),
            poolLengthMeters: 25,
            startDate: friday
        )

        for workout in plan.trainingSessions {
            let weekday = try #require(Weekday(date: workout.date, calendar: calendar))
            #expect(schedule.isAvailable(on: weekday))
            #expect(workout.date >= friday)
        }
    }

    @Test("A Monday start gives a full seven-day week")
    func mondayStartGivesFullWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var builder = FirstWeekBuilder()
        builder.calendar = calendar

        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)))
        let plan = try builder.build(setup: setup(), poolLengthMeters: 25, startDate: monday, weekNumber: 3)

        #expect(plan.startDate == monday)
        #expect(plan.weekNumber == 3)
        #expect(plan.orderedWorkouts.count == 7)
        #expect(calendar.dateComponents([.day], from: plan.startDate, to: plan.endDate).day == 6)
    }

    @Test("A sport the athlete does not want is not prescribed")
    func unwantedSportIsAbsent() throws {
        let plan = try builder.build(
            setup: setup(preferences: [
                SportPreference(sport: .running, sessionsPerWeek: 2),
                SportPreference(sport: .swimming, sessionsPerWeek: 0),
                SportPreference(sport: .cycling, sessionsPerWeek: 2)
            ]),
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.orderedWorkouts.contains { $0.discipline == .swimming } == false)
        #expect(plan.orderedWorkouts.contains { $0.discipline == .running })
    }

    @Test("A day too short for a session is not used for it")
    func durationLimitsAreHonoured() throws {
        // Every day capped below even the shortest ride, so cycling cannot fit.
        let schedule = AthleteSchedule.everyDay(maxDurationMinutes: 15)

        let plan = try? builder.build(
            setup: setup(
                cycling: .sixtyPlus,
                schedule: schedule,
                preferences: [SportPreference(sport: .cycling, sessionsPerWeek: 2, typicalMinutes: 75)]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan == nil)
    }

    @Test("An unusable schedule fails explicitly rather than producing a bad week")
    func unusableScheduleThrows() {
        #expect(throws: FirstWeekBuilder.BuildFailure.scheduleUnusable) {
            try builder.build(setup: setup(schedule: .empty), poolLengthMeters: 25)
        }
    }

    @Test("A single available day is not enough to plan a week")
    func oneDayIsNotEnough() {
        let schedule = AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(weekday: $0, isAvailable: $0 == .saturday)
            }
        )

        #expect(throws: FirstWeekBuilder.BuildFailure.scheduleUnusable) {
            try builder.build(setup: setup(schedule: schedule), poolLengthMeters: 25)
        }
    }

    @Test("The pool the athlete swims in reaches the prescription")
    func poolLengthReachesTheWorkout() throws {
        let plan = try builder.build(
            setup: setup(swimming: .continuous100),
            poolLengthMeters: 50
        )

        #expect(plan.parameters.swimPoolLengthMeters == 50)
        #expect(plan.parameters.swimRepeatDistanceMeters == 50)

        let swim = try #require(plan.orderedWorkouts.first { $0.discipline == .swimming })
        let total = try #require(swim.estimatedDistanceMeters)
        #expect(total.truncatingRemainder(dividingBy: 50) == 0)
    }

    @Test("Building is deterministic")
    func buildingIsDeterministic() throws {
        let athlete = setup()

        let first = try builder.build(setup: athlete, poolLengthMeters: 25, startDate: monday())
        let second = try builder.build(setup: athlete, poolLengthMeters: 25, startDate: monday())

        #expect(first.parameters == second.parameters)
        #expect(first.orderedWorkouts.map(\.discipline) == second.orderedWorkouts.map(\.discipline))
    }

    @Test("Rest days are left in rather than every day being filled")
    func weekIsNotPackedFull() throws {
        let plan = try builder.build(setup: setup(), poolLengthMeters: 25, startDate: monday())

        #expect(plan.orderedWorkouts.contains { $0.discipline == .rest })
        #expect(plan.trainingSessions.count <= 6)
    }
}
