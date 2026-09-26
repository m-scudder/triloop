import Foundation
import Testing

@testable import Athevia

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

    @Test("Available days define the number of training slots")
    func availableDaysAreFilled() {
        let shape = planner.plan(
            schedule: everyDay,
            frequencies: WeekShapePlanner.frequencies(
                from: preferences(run: 2, swim: 2, cycle: 2),
                schedule: everyDay
            )
        )

        #expect(shape.disciplines.filter(\.isTrainingSession).count == 7)
        #expect(shape.disciplines.contains(.rest) == false)
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

    @Test("Selected sports split the available days")
    func selectedSportsSplitAvailableDays() {
        let plan = schedule([.tuesday, .thursday])

        let frequencies = WeekShapePlanner.frequencies(
            from: preferences(run: 3, swim: 2),
            schedule: plan
        )

        #expect(frequencies.first { $0.sport == .running }?.sessions == 1)
        #expect(frequencies.first { $0.sport == .swimming }?.sessions == 1)
        #expect(frequencies.contains { $0.sport == .cycling } == false)
    }

    @Test("Six Run and Cycle days split three and three")
    func runCycleSixDaySplit() {
        let plan = schedule([.tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])

        let frequencies = WeekShapePlanner.frequencies(
            from: preferences(run: 1, cycle: 1),
            schedule: plan
        )

        #expect(frequencies.first { $0.sport == .running }?.sessions == 3)
        #expect(frequencies.first { $0.sport == .cycling }?.sessions == 3)
    }

    @Test("Opening capacity leaves recovery room for a multisport beginner")
    func beginnerCapacityDoesNotFillSixDays() {
        let plan = schedule([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        let baseline = AthleteBaseline(
            running: .none,
            swimming: .none,
            cycling: .under20
        )

        let frequencies = WeekShapePlanner.frequencies(
            for: Sport.allCases,
            schedule: plan,
            baseline: baseline
        )

        #expect(frequencies.reduce(0) { $0 + $1.sessions } == 3)
        #expect(frequencies.allSatisfy { $0.sessions == 1 })
    }

    @Test("Established multisport ability can use all six available days")
    func establishedCapacityUsesSixDays() {
        let plan = schedule([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        let baseline = AthleteBaseline(
            running: .regular5K,
            swimming: .continuous200Plus,
            cycling: .sixtyPlus
        )

        let frequencies = WeekShapePlanner.frequencies(
            for: Sport.allCases,
            schedule: plan,
            baseline: baseline
        )

        #expect(frequencies.reduce(0) { $0 + $1.sessions } == 6)
        #expect(frequencies.allSatisfy { $0.sessions == 2 })
    }

    @Test("Running only uses non-consecutive available days")
    func runningOnlyLeavesRecoverySlots() {
        let plan = schedule([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])

        let frequencies = WeekShapePlanner.frequencies(
            from: preferences(run: 1),
            schedule: plan
        )

        #expect(frequencies.first { $0.sport == .running }?.sessions == 3)
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
    @Test("Cycling-only can use every selected day even for a beginner")
    func cyclingUsesSelectedAvailability() {
        let baseline = AthleteBaseline(cycling: .under20)
        let frequencies = WeekShapePlanner.frequencies(
            for: [.cycling],
            schedule: everyDay,
            baseline: baseline
        )

        #expect(frequencies == [SportFrequency(sport: .cycling, sessions: 7)])
    }

    @Test("Beginner swimming uses selected days with a conservative frequency ceiling")
    func beginnerSwimmingKeepsRecoveryRoom() {
        let baseline = AthleteBaseline(swimming: .none)
        let frequencies = WeekShapePlanner.frequencies(
            for: [.swimming],
            schedule: everyDay,
            baseline: baseline
        )

        #expect(frequencies == [SportFrequency(sport: .swimming, sessions: 5)])
    }

    @Test("Recorded training can increase future frequency without changing onboarding")
    func capabilityEvidenceCanIncreaseFrequency() {
        let sixDays = schedule([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        let setup = AthleteSetup(
            baseline: AthleteBaseline(running: .runWalk),
            schedule: sixDays,
            preferences: [SportPreference(sport: .running, sessionsPerWeek: 1)]
        )
        let asOf = Date(timeIntervalSince1970: 1_788_000_000)
        let capabilityBuilder = AthleteCapabilityAssessmentBuilder()

        let openingCapability = capabilityBuilder.build(
            setup: setup,
            plans: [],
            asOf: asOf
        )
        let opening = WeekShapePlanner.frequencies(
            for: [.running],
            schedule: sixDays,
            capability: openingCapability
        )

        let runDate = asOf.addingTimeInterval(-24 * 60 * 60)
        let completedRun = PlannedWorkout(
            date: runDate,
            discipline: .running,
            title: "Recorded run"
        )
        completedRun.attach(
            ImportedWorkoutSummary(
                healthKitUUID: UUID(),
                sport: .running,
                startDate: runDate,
                endDate: runDate.addingTimeInterval(30 * 60),
                duration: 30 * 60,
                distanceMeters: 5_000,
                source: "Test"
            )
        )
        completedRun.recordCompletion(
            with: FeedbackDraft(rpe: 4, painScore: 0, recoveryFeeling: .good),
            at: runDate.addingTimeInterval(30 * 60)
        )
        let history = WeeklyPlan(
            weekNumber: 1,
            startDate: runDate,
            endDate: runDate,
            parameters: TrainingParameters(),
            workouts: [completedRun]
        )
        let progressedCapability = capabilityBuilder.build(
            setup: setup,
            plans: [history],
            asOf: asOf
        )
        let progressed = WeekShapePlanner.frequencies(
            for: [.running],
            schedule: sixDays,
            capability: progressedCapability
        )

        #expect(opening.first?.sessions == 2)
        #expect(progressedCapability.running.recentBestDistanceMeters == 5_000)
        #expect(progressed.first?.sessions == 3)
        #expect(setup.baseline.running == .runWalk)
    }

    @Test("Journey priority reallocates capacity but never creates extra training days")
    func priorityDoesNotIncreaseCapacity() {
        let sixDays = schedule([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        let baseline = AthleteBaseline(
            running: .continuous20To30Minutes,
            swimming: .continuous25,
            cycling: .twentyToThirty
        )
        let frequencies = WeekShapePlanner.frequencies(
            for: Sport.allCases,
            schedule: sixDays,
            baseline: baseline,
            priorities: [
                SportPriority(sport: .swimming, rank: 1, reason: "Largest event gap"),
                SportPriority(sport: .cycling, rank: 2, reason: "Maintain cycling"),
                SportPriority(sport: .running, rank: 3, reason: "Maintain running")
            ]
        )

        #expect(frequencies.reduce(0) { $0 + $1.sessions } == 4)
        #expect(frequencies.first { $0.sport == .swimming }?.sessions == 2)
        #expect(frequencies.first { $0.sport == .cycling }?.sessions == 1)
        #expect(frequencies.first { $0.sport == .running }?.sessions == 1)
    }

}
