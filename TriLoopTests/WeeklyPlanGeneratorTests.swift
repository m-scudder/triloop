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
        WeeklyPlanGenerator(calendar: calendar)
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
        #expect(week2.orderedWorkouts.map(\.discipline) == [
            .running, .swimming, .recovery, .running, .swimming, .cycling, .rest
        ])
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

    @Test("Swimming tightens rest before adding distance")
    func swimmingTightensRestFirst() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)
        #expect(week2.parameters.swimRestSeconds == 30)
        #expect(week2.parameters.swimTotalMeters == 300)

        completeEverything(week2, with: FeedbackDraft(rpe: 3, painScore: 0))
        let week3 = nextWeek(after: week2)

        #expect(week3.parameters.swimRestSeconds == 30)
        #expect(week3.parameters.swimTotalMeters == 350)
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
        #expect(week2.orderedWorkouts.allSatisfy { $0.discipline == .recovery || $0.discipline == .rest })
    }

    @Test("Generation records why the week looks the way it does")
    func generationReasonIsRecorded() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)

        #expect(week2.generationReason.isEmpty == false)
        #expect(week2.generationReason.contains("Running"))
    }

    @Test("Sessions are renumbered within the new week")
    func sessionsAreRenumbered() {
        let week1 = seededWeek()
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))

        let week2 = nextWeek(after: week1)
        let runs = week2.orderedWorkouts.filter { $0.discipline == .running }

        #expect(runs.count == 2)
        #expect(runs[0].title.hasSuffix("#1"))
        #expect(runs[1].title.hasSuffix("#2"))
    }

    @Test("The following week is only ever created once")
    func generationIsNotRepeatable() throws {
        let context = ModelContext(try TriLoopModelContainer.make(inMemory: true))
        let week1 = seededWeek()
        context.insert(week1)
        completeEverything(week1, with: FeedbackDraft(rpe: 3, painScore: 0))
        try context.save()

        let store = PlanStore(context: context, generator: generator())

        #expect(store.generateNextWeek(after: week1) != nil)
        #expect(store.generateNextWeek(after: week1) == nil)

        let plans = try context.fetch(FetchDescriptor<WeeklyPlan>())
        #expect(plans.count == 2)
        #expect(week1.status == .completed)
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
