import Foundation
import Testing

@testable import Athevia

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

    @Test("Previously sent plain titles are refreshed once without moving the workout")
    func legacyNamesAreRefreshed() async throws {
        let plan = plan()
        let entries = plan.trainingSessions.map { workout in
            ScheduledWorkoutSummary(
                id: workout.id,
                displayName: workout.title,
                date: workout.suggestedScheduleDate(now: date(day: 17), calendar: calendar),
                isComplete: false
            )
        }
        let stub = StubWorkoutScheduler(entries: entries)
        let scheduler = weekScheduler(stub)

        // Sync later: the rename must retain the original scheduled time.
        let outcome = await scheduler.scheduleWeek(plan, now: date(day: 17, hour: 12))
        #expect(outcome.removed == entries.count)
        #expect(outcome.added == entries.count)
        #expect(outcome.failed == 0)

        let updated = await stub.scheduledWorkouts()
        #expect(updated.count == entries.count)
        for original in entries {
            let entry = try #require(updated.first { $0.id == original.id })
            #expect(entry.date == original.date)
            #expect(entry.displayName == "Athevia - " + (original.displayName ?? ""))
        }

        let again = await scheduler.scheduleWeek(plan, now: date(day: 17, hour: 13))
        #expect(!again.changedAnything)
        #expect(again.alreadyScheduled == entries.count)
    }

    @Test("Renaming preserves a Watch completion waiting to import")
    func completedWatchEntryIsNotRenamed() async throws {
        let plan = plan()
        let workout = try #require(plan.trainingSessions.first)
        let completed = ScheduledWorkoutSummary(
            id: workout.id,
            displayName: workout.title,
            date: date(day: 17, hour: 7),
            isComplete: true
        )
        let stub = StubWorkoutScheduler(entries: [completed])

        let outcome = await weekScheduler(stub).scheduleWeek(plan, now: date(day: 17))

        #expect(outcome.removed == 0)
        #expect(outcome.alreadyScheduled == 1)
        let entries = await stub.scheduledWorkouts()
        #expect(entries.first { $0.id == workout.id } == completed)
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


    @Test("Moving a scheduled ride to today updates the Watch date once")
    func movedRideFollowsPlannedDay() async throws {
        let plan = plan()
        let ride = try #require(plan.trainingSessions.first { $0.discipline == .cycling })
        let stub = StubWorkoutScheduler()
        let scheduler = weekScheduler(stub)
        _ = await scheduler.scheduleWeek(plan, now: date(day: 17))

        ride.date = date(day: 17, hour: 0)
        let outcome = await scheduler.scheduleWeek(plan, now: date(day: 17))
        let entries = await stub.scheduledWorkouts()
        let updated = try #require(entries.first { $0.id == ride.id })
        let scheduledDate = try #require(updated.date)

        #expect(outcome.removed == 1)
        #expect(outcome.added == 1)
        #expect(calendar.isDate(scheduledDate, inSameDayAs: ride.date))
        #expect(entries.filter { $0.id == ride.id }.count == 1)

        let again = await scheduler.scheduleWeek(plan, now: date(day: 17, hour: 12))
        #expect(!again.changedAnything)
    }

    @Test("A completed Watch workout is preserved even if its planned date changes")
    func movedCompletedEntryIsPreserved() async throws {
        let plan = plan()
        let ride = try #require(plan.trainingSessions.first { $0.discipline == .cycling })
        let completed = ScheduledWorkoutSummary(
            id: ride.id,
            displayName: WorkoutPlanBuilder.displayName(for: ride),
            date: ride.suggestedScheduleDate(now: date(day: 17), calendar: calendar),
            isComplete: true
        )
        let stub = StubWorkoutScheduler(entries: [completed])
        ride.date = date(day: 17, hour: 0)

        _ = await weekScheduler(stub).scheduleWeek(plan, now: date(day: 17))
        let entries = await stub.scheduledWorkouts()
        #expect(entries.first { $0.id == ride.id } == completed)
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
