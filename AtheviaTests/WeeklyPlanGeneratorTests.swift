import Foundation
import SwiftData
import Testing

@testable import Athevia

@Suite("Weekly plan generation")
@MainActor
struct WeeklyPlanGeneratorTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func monday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        return calendar.date(from: components) ?? .now
    }

    private func seededWeek() -> WeeklyPlan {
        SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
    }

    private func generator() -> WeeklyPlanGenerator {
        WeeklyPlanGenerator(schedule: .everyDay(), calendar: calendar)
    }

    private func nextWeek(after plan: WeeklyPlan) -> WeeklyPlan {
        generator().generate(after: plan, analysis: WeeklyAnalyser().analyse(plan))
    }

    private func completeEverything(_ plan: WeeklyPlan, with draft: FeedbackDraft) {
        for workout in plan.trainingSessions {
            workout.recordCompletion(with: draft)
        }
    }

    @Test("The next week follows on immediately and keeps its shape")
    func nextWeekFollowsOn() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)

        #expect(week2.weekNumber == 2)
        #expect(week2.startDate == calendar.date(byAdding: .day, value: 7, to: week1.startDate))
        #expect(calendar.dateComponents([.day], from: week2.startDate, to: week2.endDate).day == 6)
        // Placement now follows availability, so the week is asserted by what it
        // contains rather than by a fixed Monday-to-Sunday order.
        #expect(week2.orderedWorkouts.count == 7)
        #expect(week2.trainingSessions.filter { $0.discipline == .running }.count == 2)
        #expect(week2.trainingSessions.filter { $0.discipline == .swimming }.count == 2)
        #expect(week2.trainingSessions.filter { $0.discipline == .cycling }.count == 2)
        #expect(week2.orderedWorkouts.filter { $0.discipline == .rest }.count == 1)
        #expect(week2.orderedWorkouts.filter { $0.discipline == .recovery }.isEmpty)
        #expect(week2.status == .active)
    }

    @Test("A good week lengthens the running interval only")
    func goodWeekProgressesRunning() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)

        #expect(week2.parameters.runIntervalSeconds == 75)
        #expect(week2.parameters.runRepeatCount == 6)
        #expect(week2.parameters.runWalkSeconds == 120)

        let run = week2.orderedWorkouts.first { $0.discipline == .running }
        // 5 min warm-up + 6 × (1:15 run + 2:00 walk) + 5 min cooldown.
        #expect(run?.estimatedDurationSeconds == TimeInterval(1770))
    }

    @Test("A good week adds five minutes to the ride")
    func goodWeekProgressesCycling() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)
        let ride = week2.orderedWorkouts.first { $0.discipline == .cycling }

        #expect(week2.parameters.rideWorkSeconds == TimeInterval(25 * 60))
        #expect(ride?.estimatedDurationSeconds == TimeInterval(35 * 60))
    }

    @Test("Sustained demonstrated cycling can advance by ten work minutes")
    func sustainedCyclingEvidenceAcceleratesProgression() {
        let week1 = seededWeek()
        for workout in week1.trainingSessions {
            workout.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        }

        var generator = generator()
        generator.capability = AthleteCapabilityAssessment(
            running: RunningCapability(
                reportedContinuousSeconds: nil,
                prescribedContinuousSeconds: nil,
                demonstratedContinuousSeconds: nil,
                longestRecordedDistanceMeters: 0,
                recentDirection: .holding
            ),
            cycling: CyclingCapability(
                reportedComfortableSeconds: 20 * 60,
                prescribedWorkSeconds: 20 * 60,
                bestRecentDurationSeconds: 40 * 60,
                longestRecordedDistanceMeters: 10_000,
                recentDirection: .building
            ),
            swimming: SwimmingCapability(
                foundationState: .waterComfort,
                reportedContinuousMeters: nil,
                prescribedRepeatMeters: 25,
                prescribedTotalWorkoutMeters: 300,
                longestProvenContinuousMeters: nil,
                longestRecordedTotalWorkoutMeters: 0,
                openWaterExperience: false,
                recentDirection: .holding
            ),
            recentCompletedSessions: 10,
            recentPlannedSessions: 10,
            recentMissedOrSkippedSessions: 0,
            recentAdherence: 1,
            recoveryState: .stable,
            completedBrickCount: 0
        )

        let week2 = generator.generate(after: week1, analysis: WeeklyAnalyser().analyse(week1))

        // 40 min demonstrated total - 10 min warm-up/cooldown = 30 min work.
        // That is a meaningful 10-minute step from the 20-minute work block,
        // rather than forcing the athlete through 21, 22, 23... minute weeks.
        #expect(week2.parameters.rideWorkSeconds == TimeInterval(30 * 60))
    }

    @Test("Sustained history never overrides a cycling safety hold")
    func sustainedCyclingEvidenceDoesNotOverrideSafety() {
        let week1 = seededWeek()
        for workout in week1.trainingSessions where workout.discipline == .cycling {
            workout.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 3))
        }
        for workout in week1.trainingSessions where workout.discipline != .cycling {
            workout.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        }

        var generator = generator()
        generator.capability = AthleteCapabilityAssessment(
            running: RunningCapability(
                reportedContinuousSeconds: nil,
                prescribedContinuousSeconds: nil,
                demonstratedContinuousSeconds: nil,
                longestRecordedDistanceMeters: 0,
                recentDirection: .holding
            ),
            cycling: CyclingCapability(
                reportedComfortableSeconds: 20 * 60,
                prescribedWorkSeconds: 20 * 60,
                bestRecentDurationSeconds: 60 * 60,
                longestRecordedDistanceMeters: 20_000,
                recentDirection: .building
            ),
            swimming: SwimmingCapability(
                foundationState: .waterComfort,
                reportedContinuousMeters: nil,
                prescribedRepeatMeters: 25,
                prescribedTotalWorkoutMeters: 300,
                longestProvenContinuousMeters: nil,
                longestRecordedTotalWorkoutMeters: 0,
                openWaterExperience: false,
                recentDirection: .holding
            ),
            recentCompletedSessions: 10,
            recentPlannedSessions: 10,
            recentMissedOrSkippedSessions: 0,
            recentAdherence: 1,
            recoveryState: .stable,
            completedBrickCount: 0
        )

        let week2 = generator.generate(after: week1, analysis: WeeklyAnalyser().analyse(week1))
        #expect(week2.parameters.rideWorkSeconds == week1.parameters.rideWorkSeconds)
    }

    @Test("Swimming tightens rest, then lengthens the repeat")
    func swimmingTightensRestThenLengthensRepeat() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)
        #expect(week2.parameters.swimRestSeconds == 30)
        #expect(week2.parameters.swimRepeatDistanceMeters == 25)
        #expect(week2.parameters.swimTotalMeters == 300)

        completeEverything(week2, with: FeedbackDraft(rpe: 3, painScore: 0))
        let week3 = nextWeek(after: week2)

        // Rest is at its floor for a 25 m repeat, so continuity is the next
        // lever rather than more broken lengths.
        #expect(week3.parameters.swimRepeatDistanceMeters == 50)
        #expect(week3.parameters.swimTotalMeters == 300)
        #expect(week3.parameters.swimRestSeconds == 75)

        completeEverything(week3, with: FeedbackDraft(rpe: 3, painScore: 0))
        let week4 = nextWeek(after: week3)

        // Rest again, not another jump in continuity.
        #expect(week4.parameters.swimRepeatDistanceMeters == 50)
        #expect(week4.parameters.swimRestSeconds == 60)
    }

    @Test("An unreported week repeats itself")
    func unreportedWeekRepeats() {
        let week1 = seededWeek()
        let week2 = nextWeek(after: week1)

        #expect(week2.parameters == week1.parameters)
        #expect(week2.weekNumber == 2)
    }

    @Test("A sport sent to recovery is not prescribed next week")
    func recoveringSportBecomesRecovery() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 2, painScore: 9))

        let week2 = nextWeek(after: week1)

        #expect(week2.orderedWorkouts.contains { $0.discipline == .running } == false)
        #expect(week2.orderedWorkouts.contains { $0.discipline == .cycling } == false)
        #expect(week2.orderedWorkouts.allSatisfy { !$0.discipline.isTrainingSession })
    }

    @Test("Recovery replaces the sessions pulled, not the whole week")
    func recoveryDoesNotFloodTheWeek() {
        let week1 = seededWeek()
        // Running only: enough pain to pull it, not enough to stop everything.
        for run in week1.trainingSessions where run.discipline == .running {
            run.recordCompletion(with: FeedbackDraft(rpe: 2, painScore: 9))
        }
        for other in week1.trainingSessions where other.discipline != .running {
            other.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        }

        let week2 = nextWeek(after: week1)
        let recovery = week2.orderedWorkouts.filter { $0.discipline == .recovery }

        // The two pulled runs plus the otherwise-unused available day are
        // recovery now; an available day is never silently changed to Rest.
        #expect(recovery.count == 3)
        #expect(week2.orderedWorkouts.contains { $0.discipline == .rest } == false)
        #expect(week2.orderedWorkouts.contains { $0.discipline == .swimming })
    }

    @Test("A week with nothing to report can still be closed")
    func recoveryWeekIsReady() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 2, painScore: 9))

        let week2 = nextWeek(after: week1)
        let analysis = WeeklyAnalyser().analyse(week2)

        #expect(analysis.plannedSessions == 0)
        // Otherwise the athlete is stranded on a week that can never complete.
        #expect(analysis.isReadyForNextWeek)
    }

    @Test("Training resumes after a week that carried no sessions")
    func trainingResumesAfterRecovery() {
        var generator = WeeklyPlanGenerator(schedule: .everyDay(), calendar: calendar)
        generator.preferences = [
            SportPreference(sport: .running, sessionsPerWeek: 2, typicalMinutes: 45),
            SportPreference(sport: .swimming, sessionsPerWeek: 1, typicalMinutes: 45)
        ]

        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 2, painScore: 9))
        let recoveryWeek = generator.generate(after: week1, analysis: WeeklyAnalyser().analyse(week1))

        let week3 = generator.generate(
            after: recoveryWeek,
            analysis: WeeklyAnalyser().analyse(recoveryWeek)
        )

        #expect(week3.trainingSessions.isEmpty == false)
        #expect(week3.trainingSessions.filter { $0.discipline == .running }.count == 3)
        #expect(week3.trainingSessions.filter { $0.discipline == .swimming }.count == 4)
        #expect(week3.orderedWorkouts.contains { $0.discipline == .rest } == false)
    }
    @Test("Generation records why the week looks the way it does")
    func generationReasonIsRecorded() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)

        #expect(week2.generationReason.isEmpty == false)
        #expect(week2.generationReason.contains("Running"))
    }

    @Test("Generated sessions carry the sport's name")
    func sessionsAreNamedBySport() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)
        let runs = week2.orderedWorkouts.filter { $0.discipline == .running }

        #expect(runs.count == 2)
        #expect(runs.allSatisfy { $0.title == "Running" })
    }

    @Test("The following week is only ever created once")
    func generationIsNotRepeatable() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let week1 = seededWeek()
        context.insert(week1)
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))
        try context.save()

        let store = PlanStore(context: context, generator: generator())

        #expect(try store.generateNextWeek(after: week1) != nil)
        #expect(try store.generateNextWeek(after: week1) == nil)

        let plans = try context.fetch(FetchDescriptor<WeeklyPlan>())
        #expect(plans.count == 2)
        #expect(week1.status == .completed)
    }

    @Test("A fully reported week advances without a separate generate action")
    func completedWeekAdvancesAutomatically() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let week1 = seededWeek()
        context.insert(week1)
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))
        try context.save()

        let store = PlanStore(context: context, generator: generator())
        let week2 = try #require(try store.generateNextWeekIfReady(after: week1))

        #expect(week1.status == .completed)
        #expect(week2.weekNumber == 2)
        #expect([week1, week2].currentPlan(on: week1.startDate, calendar: calendar)?.weekNumber == 2)
        #expect(try store.generateNextWeekIfReady(after: week1) == nil)
    }

    @Test("The current week is the one containing today, not the newest")
    func currentPlanPrefersTheWeekInProgress() {
        let week1 = seededWeek()
        let week2 = nextWeek(after: week1)
        let plans = [week2, week1]

        let wednesday = calendar.date(byAdding: .day, value: 2, to: week1.startDate) ?? week1.startDate
        #expect(plans.currentPlan(on: wednesday, calendar: calendar)?.weekNumber == 1)

        let nextTuesday = calendar.date(byAdding: .day, value: 8, to: week1.startDate) ?? week1.startDate
        #expect(plans.currentPlan(on: nextTuesday, calendar: calendar)?.weekNumber == 2)

        let beforeStart = calendar.date(byAdding: .day, value: -3, to: week1.startDate) ?? week1.startDate
        #expect(plans.currentPlan(on: beforeStart, calendar: calendar)?.weekNumber == 1)
    }
}

/// A week that runs out must not leave Today empty, reported or not.
@Suite("Week roll-forward")
@MainActor
struct WeekRollForwardTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func monday() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 17)) ?? .now
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday()) ?? monday()
    }

    private func makeStore() throws -> (PlanStore, ModelContext, WeeklyPlan) {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let week1 = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        context.insert(week1)
        try context.save()

        let store = PlanStore(
            context: context,
            generator: WeeklyPlanGenerator(schedule: .everyDay(), calendar: calendar)
        )
        return (store, context, week1)
    }

    @Test("A week still in progress is left alone")
    func currentWeekIsNotAdvanced() throws {
        let (store, context, week1) = try makeStore()

        #expect(try store.advanceToCurrentWeek(asOf: day(3), calendar: calendar) == nil)
        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 1)
        #expect(week1.status == .active)
    }

    @Test("The last day of the week is still part of it")
    func finalDayIsNotAnEndedWeek() throws {
        let (store, _, week1) = try makeStore()

        #expect(try store.advanceToCurrentWeek(asOf: week1.endDate, calendar: calendar) == nil)
        #expect(week1.status == .active)
    }

    @Test("A week that has ended generates the next one without any report")
    func endedWeekAdvancesUnreported() throws {
        let (store, _, week1) = try makeStore()

        let week2 = try #require(try store.advanceToCurrentWeek(asOf: day(7), calendar: calendar))

        #expect(week2.weekNumber == 2)
        #expect(week2.startDate == day(7))
        #expect(week1.status == .completed)
        #expect(week2.status == .active)
        #expect(week2.trainingSessions.isEmpty == false)
    }

    @Test("A break of several weeks catches up to the week containing today")
    func missedWeeksAreCaughtUp() throws {
        let (store, _, _) = try makeStore()

        let week4 = try #require(try store.advanceToCurrentWeek(asOf: day(23), calendar: calendar))

        #expect(week4.weekNumber == 4)
        #expect(week4.contains(day(23), calendar: calendar))
    }

    @Test("Catch-up stops at the limit rather than rebuilding a lost year")
    func catchUpIsBounded() throws {
        let (store, context, _) = try makeStore()

        let latest = try #require(
            try store.advanceToCurrentWeek(asOf: day(700), calendar: calendar, limit: 3)
        )

        #expect(latest.weekNumber == 4)
        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 4)
    }

    @Test("Advancing twice on the same day does not stack up weeks")
    func advancingIsIdempotent() throws {
        let (store, context, _) = try makeStore()

        #expect(try store.advanceToCurrentWeek(asOf: day(7), calendar: calendar) != nil)
        #expect(try store.advanceToCurrentWeek(asOf: day(7), calendar: calendar) == nil)
        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 2)
    }

    @Test("An empty store has nothing to advance")
    func emptyStoreIsUntouched() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let store = PlanStore(context: context)

        #expect(try store.advanceToCurrentWeek(asOf: monday(), calendar: calendar) == nil)
    }
}

/// A week cut short must not become the athlete's new normal.
@Suite("Frequency recovery")
@MainActor
struct TrainingFrequencyRecoveryTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func monday() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 17)) ?? .now
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday()) ?? monday()
    }

    private let asked: [SportPreference] = [
        SportPreference(sport: .running, sessionsPerWeek: 3),
        SportPreference(sport: .swimming, sessionsPerWeek: 2)
    ]

    /// A first week that began on the Friday: one run, and the rest of the week
    /// already gone.
    private func partialWeek() -> WeeklyPlan {
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: monday(),
            endDate: day(6),
            parameters: TrainingParameters()
        )

        for offset in 0..<7 {
            let discipline: Discipline = offset == 4 ? .running : .rest
            plan.workouts.append(
                PrescribedSessions.session(discipline, on: day(offset), parameters: plan.parameters)
            )
        }
        return plan
    }

    private func generator(days: AthleteSchedule = .everyDay()) -> WeeklyPlanGenerator {
        WeeklyPlanGenerator(schedule: days, preferences: asked, calendar: calendar)
    }

    private func sessions(_ plan: WeeklyPlan, _ sport: Sport) -> Int {
        plan.trainingSessions.count { $0.discipline.sport == sport }
    }

    @Test("A short first week does not cap the weeks that follow")
    func frequencyRecovers() {
        let week1 = partialWeek()
        for workout in week1.trainingSessions {
            workout.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        }

        let week2 = generator().generate(after: week1, analysis: WeeklyAnalyser().analyse(week1))

        #expect(sessions(week2, .running) == 3)
        #expect(sessions(week2, .swimming) == 4)
        #expect(week2.orderedWorkouts.contains { $0.discipline == .rest } == false)
    }

    @Test("Availability still caps what can be asked for")
    func availabilityStillCaps() {
        let twoDays = AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(weekday: $0, isAvailable: $0 == .monday || $0 == .thursday)
            }
        )

        let week2 = generator(days: twoDays)
            .generate(after: partialWeek(), analysis: WeeklyAnalyser().analyse(partialWeek()))

        #expect(week2.trainingSessions.count <= 2)
    }

    @Test("Availability defines the next week's frequency")
    func availabilityDefinesFrequency() {
        let plan = WeeklyPlan(
            weekNumber: 2,
            startDate: monday(),
            endDate: day(6),
            parameters: TrainingParameters()
        )
        // Historical frequency no longer controls the next week; selected
        // sports are redistributed across the available plan slots.
        for offset in 0..<7 {
            let discipline: Discipline = offset < 4 ? .running : .rest
            plan.workouts.append(
                PrescribedSessions.session(discipline, on: day(offset), parameters: plan.parameters)
            )
        }

        let next = generator().generate(after: plan, analysis: WeeklyAnalyser().analyse(plan))

        #expect(sessions(next, .running) == 3)
        #expect(sessions(next, .swimming) == 4)
        #expect(next.orderedWorkouts.contains { $0.discipline == .rest } == false)
    }
}
