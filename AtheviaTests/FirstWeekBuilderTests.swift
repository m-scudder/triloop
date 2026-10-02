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
        trainingDayTarget: Int = 3,
        preferences: [SportPreference]? = nil
    ) -> AthleteSetup {
        AthleteSetup(
            goal: goal,
            trainingDayTarget: trainingDayTarget,
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

    @Test("Recovery counts as a planned workout while rest does not")
    func recoveryAndRestHaveDifferentCompletionSemantics() {
        let date = monday()
        let run = PlannedWorkout(date: date, discipline: .running, title: "Run")
        let recovery = PrescribedSessions.recoveryDay(on: date.addingTimeInterval(24 * 60 * 60))
        let rest = PrescribedSessions.restDay(on: date.addingTimeInterval(2 * 24 * 60 * 60))
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: date,
            endDate: date.addingTimeInterval(6 * 24 * 60 * 60),
            workouts: [run, recovery, rest]
        )

        #expect(plan.prescribedWorkouts.count == 2)
        #expect(plan.prescribedTrainingSessions.count == 1)
        #expect(recovery.acceptsFeedback == false)
        #expect(recovery.canCompleteWithoutFeedback)
        recovery.completeWithoutFeedback()
        #expect(recovery.isCompleted)
        #expect(rest.acceptsFeedback == false)
        #expect(rest.canCompleteWithoutFeedback == false)
    }


    @Test("Two day target starts with two workouts")
    func twoDayTargetStartsAtTwo() throws {
        let plan = try builder.build(
            setup: setup(
                schedule: .everyDay(),
                trainingDayTarget: 2,
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 1)]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.prescribedTrainingSessions.count == 2)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .recovery }.isEmpty)
    }

    @Test("Three day beginner running target starts with three runs")
    func threeDayBeginnerRunStartsAtThree() throws {
        let plan = try builder.build(
            setup: setup(
                running: .none,
                schedule: .everyDay(),
                trainingDayTarget: 3,
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 1)]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.prescribedTrainingSessions.count == 3)
        #expect(plan.prescribedTrainingSessions.allSatisfy { $0.discipline == .running })
    }

    @Test("Four day target opens at three and leaves unused availability as rest")
    func fourDayTargetOpensAtThree() throws {
        let plan = try builder.build(
            setup: setup(
                schedule: .everyDay(),
                trainingDayTarget: 4,
                preferences: [SportPreference(sport: .cycling, sessionsPerWeek: 1)]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.prescribedTrainingSessions.count == 3)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .recovery }.isEmpty)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .rest }.count == 4)
        #expect(plan.generationReason.contains("builds gradually toward 4"))
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
        #expect(rides.count == 3)
        #expect(rides.allSatisfy {
            guard let duration = $0.estimatedDurationSeconds else { return false }
            return duration > 0 && duration <= TimeInterval(60 * 60)
        })
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

    @Test("Unused availability is rest rather than fake recovery")
    func availableDaysUseExperienceAwareCapacity() throws {
        let plan = try builder.build(setup: setup(), poolLengthMeters: 25, startDate: monday())

        #expect(plan.trainingSessions.count == 4)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .rest }.count == 3)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .recovery }.isEmpty)
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
        #expect(runs.allSatisfy {
            guard let duration = $0.estimatedDurationSeconds else { return false }
            return duration > 0 && duration <= TimeInterval(30 * 60)
        })
        #expect(rides.allSatisfy {
            guard let duration = $0.estimatedDurationSeconds else { return false }
            return duration > 0 && duration <= TimeInterval(60 * 60)
        })
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
        #expect(beginner.orderedWorkouts.filter { $0.discipline == .rest }.count == 3)
        #expect(beginner.orderedWorkouts.filter { $0.discipline == .recovery }.isEmpty)
        #expect(established.trainingSessions.count == 6)
        #expect(established.orderedWorkouts.filter { $0.discipline == .recovery }.isEmpty)
    }

    @Test("Running-only availability leaves rest between runs")
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
        #expect(plan.orderedWorkouts.filter { $0.discipline == .recovery }.isEmpty)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .rest }.count == 4)
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
    @Test("First week uses the shared phase-aware running prescriptions")
    func firstWeekUsesJourneyPhasePrescriptions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var phaseBuilder = FirstWeekBuilder()
        phaseBuilder.calendar = calendar
        let start = monday()

        func athlete(
            baseline: RunningBaseline,
            eventKind: EventDistanceKind,
            daysToEvent: Int
        ) -> AthleteSetup {
            var value = setup(
                running: baseline,
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 1)]
            )
            value.objective = .event(
                sport: .running,
                distance: EventDistance(kind: eventKind),
                eventDate: calendar.date(byAdding: .day, value: daysToEvent, to: start)
            )
            return value
        }

        let foundation = try phaseBuilder.build(
            setup: athlete(baseline: .runWalk, eventKind: .run5K, daysToEvent: 84),
            poolLengthMeters: 25,
            startDate: start
        )
        #expect(foundation.trainingSessions.contains { $0.title == "Run / Walk" })

        let build = try phaseBuilder.build(
            setup: athlete(baseline: .regular5K, eventKind: .run10K, daysToEvent: 56),
            poolLengthMeters: 25,
            startDate: start
        )
        #expect(build.trainingSessions.contains {
            $0.title == "Easy Run" || $0.title == "Longer Comfortable Run"
        })

        let specific = try phaseBuilder.build(
            setup: athlete(baseline: .regular5K, eventKind: .run10K, daysToEvent: 28),
            poolLengthMeters: 25,
            startDate: start
        )
        #expect(specific.trainingSessions.contains { $0.title == "Race-Specific Steady Run" })

        let taper = try phaseBuilder.build(
            setup: athlete(baseline: .regular5K, eventKind: .run10K, daysToEvent: 10),
            poolLengthMeters: 25,
            startDate: start
        )
        #expect(taper.trainingSessions.filter { $0.discipline == .running }
            .allSatisfy { $0.title == "Easy Run" })

        let raceWeek = try phaseBuilder.build(
            setup: athlete(baseline: .regular5K, eventKind: .run5K, daysToEvent: 5),
            poolLengthMeters: 25,
            startDate: start
        )
        #expect(raceWeek.trainingSessions.contains { $0.title == "Short Easy Run Before Your Event" })
    }

    @Test("Event inside first week replaces recovery or normal training")
    func eventInsideFirstWeekIsAuthoritative() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var phaseBuilder = FirstWeekBuilder()
        phaseBuilder.calendar = calendar
        let start = monday()
        let eventDate = try #require(calendar.date(byAdding: .day, value: 5, to: start))

        var athlete = setup(
            running: .runWalk,
            preferences: [SportPreference(sport: .running, sessionsPerWeek: 1)]
        )
        athlete.objective = .event(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventDate: eventDate
        )

        let plan = try phaseBuilder.build(
            setup: athlete,
            poolLengthMeters: 25,
            startDate: start
        )
        let eventWorkout = try #require(plan.orderedWorkouts.first {
            calendar.isDate($0.date, inSameDayAs: eventDate)
        })

        #expect(eventWorkout.title == "5K Run")
        #expect(eventWorkout.targetDistanceMeters == 5_000)
        #expect(plan.orderedWorkouts.filter {
            calendar.isDate($0.date, inSameDayAs: eventDate)
        }.count == 1)
    }

    @Test("Non-swimmer in a 25m pool gets supervised time-based fundamentals")
    func nonSwimmerUsesSupervisedFundamentals() throws {
        let plan = try builder.build(
            setup: setup(
                swimming: .none,
                preferences: [SportPreference(sport: .swimming, sessionsPerWeek: 1)]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )
        let swim = try #require(plan.trainingSessions.first { $0.discipline == .swimming })

        #expect(swim.title == "Swim Fundamentals")
        #expect(swim.orderedSteps.allSatisfy { $0.distanceMeters == nil })
        #expect(swim.orderedSteps.contains {
            $0.title.localizedCaseInsensitiveContains("supervised")
                || $0.instructions?.localizedCaseInsensitiveContains("supervision") == true
                || $0.instructions?.localizedCaseInsensitiveContains("supervised") == true
        })
    }

    @Test("25m swimmer in 50m pool gets supervised fundamentals, not a forced 50m repeat")
    func longerPoolDoesNotInflateBeginnerSwimCapability() throws {
        let plan = try builder.build(
            setup: setup(
                swimming: .continuous25,
                preferences: [SportPreference(sport: .swimming, sessionsPerWeek: 1)]
            ),
            poolLengthMeters: 50,
            startDate: monday()
        )
        let swim = try #require(plan.trainingSessions.first { $0.discipline == .swimming })

        #expect(swim.title == "Swim Fundamentals")
        #expect(swim.orderedSteps.allSatisfy { ($0.distanceMeters ?? 0) < 50 })
        #expect(swim.goal.localizedCaseInsensitiveContains("capability"))
    }

    @Test("Pool repeats remain valid once continuity supports the pool length")
    func supportedPoolGeometryKeepsWholeLengthRepeats() throws {
        let twentyFive = try builder.build(
            setup: setup(
                swimming: .continuous25,
                preferences: [SportPreference(sport: .swimming, sessionsPerWeek: 1)]
            ),
            poolLengthMeters: 25,
            startDate: monday()
        )
        let fifty = try builder.build(
            setup: setup(
                swimming: .continuous50,
                preferences: [SportPreference(sport: .swimming, sessionsPerWeek: 1)]
            ),
            poolLengthMeters: 50,
            startDate: monday()
        )
        let hundred = try builder.build(
            setup: setup(
                swimming: .continuous100,
                preferences: [SportPreference(sport: .swimming, sessionsPerWeek: 1)]
            ),
            poolLengthMeters: 50,
            startDate: monday()
        )

        let swim25 = try #require(twentyFive.trainingSessions.first { $0.discipline == .swimming })
        let swim50 = try #require(fifty.trainingSessions.first { $0.discipline == .swimming })
        let swim100 = try #require(hundred.trainingSessions.first { $0.discipline == .swimming })

        #expect(swim25.orderedSteps.contains {
            $0.orderedChildren.contains { $0.distanceMeters == 25 }
        })
        #expect(swim50.orderedSteps.contains {
            $0.orderedChildren.contains { ($0.distanceMeters ?? 0) >= 50 }
        })
        #expect(swim100.orderedSteps.contains {
            $0.orderedChildren.contains { ($0.distanceMeters ?? 0) >= 100 }
        })
    }

    @Test("Specific first week reuses open-water and brick eligibility without inventing race rehearsal evidence")
    func firstWeekUsesExistingMultisportPolicy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var phaseBuilder = FirstWeekBuilder()
        phaseBuilder.calendar = calendar
        let start = monday()

        var athlete = setup(
            running: .regular5K,
            swimming: .continuous200Plus,
            cycling: .sixtyPlus
        )
        athlete.objective = .event(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            eventDate: calendar.date(byAdding: .day, value: 28, to: start)
        )
        athlete.openWaterTrainingConsent = OpenWaterTrainingConsent(
            explicitlyConfirmed: true,
            hasSafeVenue: true,
            hasSupervisionOrBuddy: true
        )

        let plan = try phaseBuilder.build(
            setup: athlete,
            poolLengthMeters: 25,
            startDate: start
        )

        #expect(plan.trainingSessions.contains { $0.title == "Open-Water Preparation" })
        #expect(plan.trainingSessions.contains { $0.title == "Bike, Then Run" })
        #expect(!plan.trainingSessions.contains { $0.title == "Bike + Run Race Rehearsal" })
    }

    @Test("Four-day intent opens at three training days")
    func fourDayIntentOpensAtThree() throws {
        var athlete = setup(
            schedule: .everyDay(maxDurationMinutes: 60),
            preferences: [
                SportPreference(sport: .running, sessionsPerWeek: 1),
                SportPreference(sport: .cycling, sessionsPerWeek: 1)
            ]
        )
        athlete.trainingDayTarget = 4

        let plan = try builder.build(
            setup: athlete,
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.trainingSessions.count == 3)
        #expect(plan.generationReason.localizedCaseInsensitiveContains("builds gradually toward 4"))
    }

    @Test("Two-day intent starts with two training days")
    func twoDayIntentStartsAtTwo() throws {
        var athlete = setup(
            schedule: .everyDay(maxDurationMinutes: 60),
            preferences: [SportPreference(sport: .running, sessionsPerWeek: 1)]
        )
        athlete.trainingDayTarget = 2

        let plan = try builder.build(
            setup: athlete,
            poolLengthMeters: 25,
            startDate: monday()
        )

        #expect(plan.trainingSessions.count == 2)
    }

}
