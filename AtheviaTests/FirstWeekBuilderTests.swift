import Foundation
import Testing

@testable import Athevia

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

    @Test("First-week explanation names the structured event objective")
    func eventObjectiveAppearsInReason() throws {
        var athlete = setup(
            preferences: [
                SportPreference(sport: .running, sessionsPerWeek: 3)
            ]
        )
        athlete.objective = .event(
            sport: .running,
            distance: EventDistance(kind: .run5K)
        )

        let plan = try builder.build(
            setup: athlete,
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.generationReason.localizedCaseInsensitiveContains("5K Run"))
        #expect(!plan.generationReason.localizedCaseInsensitiveContains("improve endurance"))
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

    @Test("A daily time limit shortens the workout instead of dropping it")
    func durationLimitsCapTheWorkout() throws {
        let schedule = AthleteSchedule.everyDay(maxDurationMinutes: 60)

        let plan = try builder.build(
            setup: setup(
                cycling: .sixtyPlus,
                schedule: schedule,
                preferences: [SportPreference(sport: .cycling, sessionsPerWeek: 1, typicalMinutes: 75)]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )

        let rides = plan.trainingSessions.filter { $0.discipline == .cycling }
        #expect(rides.count == 4)
        #expect(rides.allSatisfy { $0.estimatedDurationSeconds == TimeInterval(60 * 60) })
        #expect(plan.parameters.rideWorkSeconds == TimeInterval(50 * 60))
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
        // Anchored like every other case here: without a start date the week
        // begins today, and days already elapsed become rest — which silently
        // removes the swim on some weekdays.
        let plan = try builder.build(
            setup: setup(swimming: .continuous100),
            poolLengthMeters: 50,
            startDate: monday()
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

    @Test("Availability is a ceiling and unused days become recovery")
    func availableDaysUseExperienceAwareCapacity() throws {
        let plan = try builder.build(setup: setup(), poolLengthMeters: 25, startDate: monday())

        #expect(plan.orderedWorkouts.contains { $0.discipline == .rest } == false)
        #expect(plan.trainingSessions.count == 4)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .recovery }.count == 3)
    }

    @Test("Experienced Run and Cycle uses five of six available days")
    func runCycleScenarioUsesExperienceAwareCapacity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var builder = FirstWeekBuilder()
        builder.calendar = calendar

        let schedule = AthleteSchedule(
            days: Weekday.trainingWeek.map { weekday in
                TrainingAvailability(
                    weekday: weekday,
                    isAvailable: weekday != .monday,
                    maxDurationMinutes: 60
                )
            }
        )
        let tuesday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))
        )

        let plan = try builder.build(
            setup: setup(
                running: .continuous20To30Minutes,
                cycling: .sixtyPlus,
                schedule: schedule,
                preferences: [
                    SportPreference(sport: .running, sessionsPerWeek: 1),
                    SportPreference(sport: .cycling, sessionsPerWeek: 1)
                ]
            ),
            poolLengthMeters: 25,
            startDate: tuesday
        )

        let runs = plan.trainingSessions.filter { $0.discipline == .running }
        let rides = plan.trainingSessions.filter { $0.discipline == .cycling }

        #expect(plan.trainingSessions.count == 5)
        #expect(runs.count == 2)
        #expect(rides.count == 3)
        #expect(runs.allSatisfy { $0.estimatedDurationSeconds == TimeInterval(30 * 60) })
        #expect(rides.allSatisfy { $0.estimatedDurationSeconds == TimeInterval(60 * 60) })
        #expect(plan.parameters.rideWorkSeconds == TimeInterval(50 * 60))

        let plannedDays = plan.orderedWorkouts.filter {
            Weekday(date: $0.date, calendar: calendar) != .monday
        }
        #expect(plannedDays.allSatisfy { $0.discipline != .rest })
    }

    @Test("The same six-day availability produces different plans by starting ability")
    func experienceChangesWeeklyArchitecture() throws {
        let schedule = AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(
                    weekday: $0,
                    isAvailable: $0 != .sunday,
                    maxDurationMinutes: 60
                )
            }
        )
        let sports = [
            SportPreference(sport: .running, sessionsPerWeek: 1),
            SportPreference(sport: .swimming, sessionsPerWeek: 1),
            SportPreference(sport: .cycling, sessionsPerWeek: 1)
        ]

        let beginner = try builder.build(
            setup: setup(
                running: .none,
                swimming: .none,
                cycling: .under20,
                schedule: schedule,
                preferences: sports
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )
        let established = try builder.build(
            setup: setup(
                running: .regular5K,
                swimming: .continuous200Plus,
                cycling: .sixtyPlus,
                schedule: schedule,
                preferences: sports
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(beginner.trainingSessions.count == 3)
        #expect(beginner.orderedWorkouts.filter { $0.discipline == .recovery }.count == 3)
        #expect(established.trainingSessions.count == 6)
        #expect(established.orderedWorkouts.filter { $0.discipline == .recovery }.isEmpty)
    }

    @Test("Running-only availability uses recovery between runs")
    func runningOnlyUsesRecoverySlots() throws {
        let schedule = AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(
                    weekday: $0,
                    isAvailable: $0 != .sunday,
                    maxDurationMinutes: 60
                )
            }
        )

        let plan = try builder.build(
            setup: setup(
                running: .continuous20To30Minutes,
                schedule: schedule,
                preferences: [
                    SportPreference(sport: .running, sessionsPerWeek: 1)
                ]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.orderedWorkouts.filter { $0.discipline == .running }.count == 3)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .recovery }.count == 3)
        #expect(plan.orderedWorkouts.last?.discipline == .rest)
    }

    @Test("A 30 minute cap preserves warm-up and cooldown")
    func thirtyMinuteCapShortensMainWork() throws {
        let schedule = AthleteSchedule.everyDay(maxDurationMinutes: 30)

        let plan = try builder.build(
            setup: setup(
                running: .regular5K,
                cycling: .sixtyPlus,
                schedule: schedule,
                preferences: [
                    SportPreference(sport: .running, sessionsPerWeek: 1),
                    SportPreference(sport: .cycling, sessionsPerWeek: 1)
                ]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.parameters.runContinuousSeconds == TimeInterval(20 * 60))
        #expect(plan.parameters.rideWorkSeconds == TimeInterval(20 * 60))
        #expect(plan.trainingSessions.allSatisfy {
            ($0.estimatedDurationSeconds ?? 0) <= TimeInterval(30 * 60)
        })
    }
}
