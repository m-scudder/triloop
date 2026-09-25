import Foundation
import SwiftData
import Testing

@testable import Athevia

@Suite("Whole-week shifting")
@MainActor
struct WeekShiftTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func monday() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 17)) ?? .now
    }

    @Test("Whole-week shifting is retired and leaves the plan unchanged")
    func wholeWeekShiftIsRetired() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        context.insert(plan)
        try context.save()

        let before = plan.orderedWorkouts.map { ($0.id, $0.date, $0.discipline, $0.status) }
        let store = PlanStore(context: context)

        #expect(throws: PlanReshaper.Failure.useSingleWorkoutMove) {
            try store.shiftWeekForward(plan, from: monday(), calendar: calendar)
        }

        let after = plan.orderedWorkouts.map { ($0.id, $0.date, $0.discipline, $0.status) }
        #expect(before.count == after.count)
        for (left, right) in zip(before, after) {
            #expect(left.0 == right.0)
            #expect(left.1 == right.1)
            #expect(left.2 == right.2)
            #expect(left.3 == right.3)
        }
    }
}
