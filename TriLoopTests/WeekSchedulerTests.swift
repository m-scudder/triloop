import Foundation
import Testing

@testable import TriLoop

@Suite("Week scheduling")
@MainActor
struct WeekSchedulerTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? .now
    }

    private func plan() -> WeeklyPlan {
        SeedWeekOne.makePlan(startDate: date(day: 17, hour: 0), calendar: calendar)
    }

    private func weekScheduler(_ stub: StubWorkoutScheduler) -> WeekScheduler {
        WeekScheduler(scheduler: stub, calendar: calendar)
    }

    @Test("The whole week goes in one action")
    func schedulesEveryUpcomingSession() async {
        let stub = StubWorkoutScheduler()
        let outcome = await weekScheduler(stub).scheduleWeek(plan(), now: date(day: 17))

        #expect(outcome.added == 6)
        #expect(outcome.failed == 0)
        #expect(stub.scheduled.count == 6)
    }

    @Test("Running it again schedules nothing new")
    func schedulingIsIdempotent() async {
        let stub = StubWorkoutScheduler()
        let plan = plan()
        let scheduler = weekScheduler(stub)

        _ = await scheduler.scheduleWeek(plan, now: date(day: 17))
        let second = await scheduler.scheduleWeek(plan, now: date(day: 17))

        #expect(second.added == 0)
        #expect(second.alreadyScheduled == 6)
        #expect(stub.scheduled.count == 6)
    }

    @Test("Days that have already gone are skipped")
    func pastDaysAreSkipped() async {
        let stub = StubWorkoutScheduler()
        // Friday: Monday through Thursday have passed.
        let outcome = await weekScheduler(stub).scheduleWeek(plan(), now: date(day: 21))

        #expect(outcome.added == 2)
    }

    @Test("Sessions already reported on are not scheduled")
    func completedSessionsAreSkipped() async {
        let stub = StubWorkoutScheduler()
        let plan = plan()
        for run in plan.trainingSessions where run.discipline == .running {
            run.recordCompletion(with: FeedbackDraft(rpe: 3))
        }

        let outcome = await weekScheduler(stub).scheduleWeek(plan, now: date(day: 17))

        // Two runs reported; the two swims and two rides remain.
        #expect(outcome.added == 4)
    }

    @Test("Without a Watch nothing is attempted")
    func unsupportedDeviceDoesNothing() async {
        let stub = StubWorkoutScheduler(isSupported: false)
        let outcome = await weekScheduler(stub).scheduleWeek(plan(), now: date(day: 17))

        #expect(outcome == WeekScheduler.Outcome())
        #expect(stub.scheduled.isEmpty)
    }

    // MARK: - Clearing spent sessions

    @Test("A session reported on is taken back off the Watch")
    func reportedSessionsAreRemoved() async throws {
        let stub = StubWorkoutScheduler()
        let plan = plan()
        let scheduler = weekScheduler(stub)

        _ = await scheduler.scheduleWeek(plan, now: date(day: 17))
        #expect(stub.scheduled.count == 6)

        let run = try #require(plan.trainingSessions.first { $0.discipline == .running })
        run.recordCompletion(with: FeedbackDraft(rpe: 3))

        let outcome = await scheduler.scheduleWeek(plan, now: date(day: 17))

        #expect(outcome.removed == 1)
        #expect(stub.scheduled.count == 5)
        #expect(!stub.scheduled.contains { $0.workoutID == run.id })
    }

    @Test("Days that have gone are cleared rather than left to pile up")
    func pastSessionsAreRemoved() async {
        let stub = StubWorkoutScheduler()
        let plan = plan()
        let scheduler = weekScheduler(stub)

        _ = await scheduler.scheduleWeek(plan, now: date(day: 17))
        let friday = await scheduler.scheduleWeek(plan, now: date(day: 21))

        #expect(friday.removed == 4)
        #expect(friday.alreadyScheduled == 2)
        #expect(stub.scheduled.count == 2)
    }

    @Test("A leftover from a regenerated week does not linger")
    func staleEntriesAreRemoved() async {
        let stub = StubWorkoutScheduler()
        let scheduler = weekScheduler(stub)

        _ = await scheduler.scheduleWeek(plan(), now: date(day: 17))
        // Regenerating produces the same shape with different identifiers.
        let outcome = await scheduler.scheduleWeek(plan(), now: date(day: 17))

        #expect(outcome.removed == 6)
        #expect(outcome.added == 6)
        #expect(stub.scheduled.count == 6)
    }

    @Test("A skipped session is not left waiting on the Watch")
    func skippedSessionsAreRemoved() async throws {
        let stub = StubWorkoutScheduler()
        let plan = plan()
        let scheduler = weekScheduler(stub)

        _ = await scheduler.scheduleWeek(plan, now: date(day: 17))

        let swim = try #require(plan.trainingSessions.first { $0.discipline == .swimming })
        swim.skip()

        let outcome = await scheduler.scheduleWeek(plan, now: date(day: 17))

        #expect(outcome.removed == 1)
        #expect(!stub.scheduled.contains { $0.workoutID == swim.id })
    }

    @Test("A denied permission is reported as failure, not success")
    func deniedPermissionFails() async {
        let stub = StubWorkoutScheduler(state: .denied)
        let outcome = await weekScheduler(stub).scheduleWeek(plan(), now: date(day: 17))

        #expect(outcome.added == 0)
        #expect(outcome.failed == 6)
    }
}
