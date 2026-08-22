import Foundation
import SwiftData
import Testing
@testable import TriLoop

/// The Watch has to follow the plan, not the tab the athlete happens to be on.
@MainActor
@Suite("Watch schedule sync")
struct WatchScheduleSyncTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour)) ?? .now
    }

    private func plan() -> WeeklyPlan {
        SeedWeekOne.makePlan(startDate: date(day: 17, hour: 0), calendar: calendar)
    }

    @Test("Changing the plan sends the week without visiting Today")
    func syncSchedulesTheWeek() async {
        let stub = StubWorkoutScheduler()

        let outcome = await WatchScheduleSync.sync(plan(), scheduler: stub, now: date(day: 17))

        #expect(outcome.added == 6)
        #expect(stub.scheduled.count == 6)
    }

    @Test("A replaced session is cleared and the new one queued")
    func syncPrunesReplacedSessions() async throws {
        let stub = StubWorkoutScheduler()
        let week = plan()

        _ = await WatchScheduleSync.sync(week, scheduler: stub, now: date(day: 17))
        let removed = try #require(week.trainingSessions.first)
        week.workouts.removeAll { $0.id == removed.id }

        let outcome = await WatchScheduleSync.sync(week, scheduler: stub, now: date(day: 17))

        #expect(outcome.removed == 1)
        #expect(!stub.scheduled.contains { $0.workoutID == removed.id })
    }

    @Test("Without permission nothing is attempted")
    func deniedPermissionDoesNothing() async {
        let stub = StubWorkoutScheduler(state: .denied)

        let outcome = await WatchScheduleSync.sync(plan(), scheduler: stub, now: date(day: 17))

        #expect(outcome == WeekScheduler.Outcome())
        #expect(stub.scheduled.isEmpty)
    }

    @Test("No plan is not an error")
    func noPlan() async {
        let stub = StubWorkoutScheduler()

        #expect(await WatchScheduleSync.sync(nil, scheduler: stub) == WeekScheduler.Outcome())
    }
}
