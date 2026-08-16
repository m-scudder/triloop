import Foundation
import Testing

@testable import TriLoop

@MainActor
struct TodayFocusTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ day: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = day
        return calendar.date(from: components) ?? .now
    }

    private func plan() -> WeeklyPlan {
        SeedWeekOne.makePlan(startDate: date(17), calendar: calendar)
    }

    @Test func selectsTodaysWorkoutInsideTheWeek() {
        let focus = TodayFocus.resolve(plan: plan(), date: date(17), calendar: calendar)

        #expect(focus.kind == .today)
        #expect(focus.dayNumber == 1)
    }

    @Test func dayNumberTracksPositionInTheWeek() {
        let focus = TodayFocus.resolve(plan: plan(), date: date(20), calendar: calendar)

        #expect(focus.kind == .today)
        #expect(focus.dayNumber == 4)
    }

    @Test func fallsForwardToTheFirstSessionBeforeTheWeekStarts() {
        let plan = plan()
        let focus = TodayFocus.resolve(plan: plan, date: date(16), calendar: calendar)

        #expect(focus.kind == .upcoming)
        #expect(focus.dayNumber == 1)
        #expect(focus.workoutID == plan.orderedWorkouts.first?.id)
    }

    @Test func reportsWeekCompleteAfterTheLastDay() {
        let focus = TodayFocus.resolve(plan: plan(), date: date(24), calendar: calendar)

        #expect(focus == .weekComplete)
    }
}
