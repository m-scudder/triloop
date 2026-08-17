import Foundation
import SwiftData
import Testing

@testable import TriLoop

@Suite("Shifting a week")
@MainActor
struct WeekShiftTests {

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

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday()) ?? monday()
    }

    private func makeStore() throws -> (PlanStore, WeeklyPlan) {
        let context = ModelContext(try TriLoopModelContainer.make(inMemory: true))
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar, availability: .everything)
        context.insert(plan)
        try context.save()
        return (PlanStore(context: context), plan)
    }

    private func disciplines(_ plan: WeeklyPlan) -> [Discipline] {
        plan.orderedWorkouts.map(\.discipline)
    }

    @Test("Missing Monday rotates the rest of the week")
    func missingMondayRotatesTheWeek() throws {
        let (store, plan) = try makeStore()

        let outcome = store.shiftWeekForward(plan, from: day(0), calendar: calendar)

        #expect(disciplines(plan) == [
            .recovery, .running, .swimming, .cycling, .running, .swimming, .cycling
        ])
        #expect(outcome.moved == 6)
        #expect(outcome.dropped == nil)
    }

    @Test("The week still covers seven days")
    func weekKeepsItsShape() throws {
        let (store, plan) = try makeStore()
        store.shiftWeekForward(plan, from: day(0), calendar: calendar)

        #expect(plan.orderedWorkouts.count == 7)
        #expect(calendar.isDate(plan.orderedWorkouts.first?.date ?? .now, inSameDayAs: plan.startDate))
        #expect(calendar.isDate(plan.orderedWorkouts.last?.date ?? .now, inSameDayAs: plan.endDate))
    }

    @Test("Shifting mid-week leaves earlier days alone")
    func earlierDaysAreUntouched() throws {
        let (store, plan) = try makeStore()

        // Thursday's run is missed; Monday and Tuesday have already happened.
        store.shiftWeekForward(plan, from: day(3), calendar: calendar)

        #expect(disciplines(plan) == [
            .running, .swimming, .cycling, .recovery, .running, .swimming, .cycling
        ])
    }

    @Test("A session pushed past Sunday is reported as dropped")
    func droppedSessionIsReported() throws {
        let (store, plan) = try makeStore()
        let ridesBefore = plan.orderedWorkouts.filter { $0.discipline == .cycling }.count

        // Shift twice: the second push moves the final ride off the end.
        store.shiftWeekForward(plan, from: day(0), calendar: calendar)
        let outcome = store.shiftWeekForward(plan, from: day(1), calendar: calendar)

        #expect(outcome.dropped == .cycling)
        #expect(plan.orderedWorkouts.filter { $0.discipline == .cycling }.count == ridesBefore - 1)
    }

    @Test("A reported session is never shifted")
    func reportedSessionIsNotShifted() throws {
        let (store, plan) = try makeStore()
        let monday = try #require(plan.workout(on: day(0), calendar: calendar))
        monday.recordCompletion(with: FeedbackDraft(rpe: 3))

        let outcome = store.shiftWeekForward(plan, from: day(0), calendar: calendar)

        #expect(outcome == PlanStore.ShiftOutcome())
        #expect(disciplines(plan) == [
            .running, .swimming, .cycling, .running, .swimming, .cycling, .rest
        ])
    }

    @Test("A date outside the week does nothing")
    func outsideTheWeekIsIgnored() throws {
        let (store, plan) = try makeStore()

        let outcome = store.shiftWeekForward(plan, from: day(20), calendar: calendar)

        #expect(outcome == PlanStore.ShiftOutcome())
        #expect(plan.orderedWorkouts.count == 7)
    }

    @Test("Feedback already recorded survives the shift")
    func existingReportsSurvive() throws {
        let (store, plan) = try makeStore()
        let monday = try #require(plan.workout(on: day(0), calendar: calendar))
        monday.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 1))

        store.shiftWeekForward(plan, from: day(1), calendar: calendar)

        #expect(monday.feedback?.rpe == 4)
        #expect(calendar.isDate(monday.date, inSameDayAs: day(0)))
    }
}
