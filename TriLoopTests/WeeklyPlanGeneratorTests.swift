import Foundation
import SwiftData
import Testing

@testable import TriLoop

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
        #expect(week2.orderedWorkouts.contains { $0.discipline == .rest })
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

        // Two runs were pulled, so two recovery days replace them.
        #expect(recovery.count == 2)
        #expect(week2.orderedWorkouts.contains { $0.discipline == .rest })
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
        #expect(week3.trainingSessions.filter { $0.discipline == .running }.count == 2)
        #expect(week3.trainingSessions.filter { $0.discipline == .swimming }.count == 1)
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
        let context = ModelContext(try TriLoopModelContainer.make(inMemory: true))
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
        let context = ModelContext(try TriLoopModelContainer.make(inMemory: true))
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
