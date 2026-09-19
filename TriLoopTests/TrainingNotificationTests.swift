import Foundation
import Testing
@testable import TriLoop

@Suite("Training notifications")
struct TrainingNotificationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Notification route survives launch and is consumed once")
    func notificationRouteIsOneShot() {
        let suite = "TriLoop.TrainingNotificationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TrainingNotificationRouteStore.enqueue(.plan, defaults: defaults)

        #expect(TrainingNotificationRouteStore.consume(defaults: defaults) == .plan)
        #expect(TrainingNotificationRouteStore.consume(defaults: defaults) == nil)
    }

    @Test("Workout reminder uses the training day and preferred clock time")
    func workoutReminderTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = calendar.date(byAdding: .day, value: 2, to: now)!

        let reminder = NotificationSchedulePolicy.workoutReminderDate(
            workoutDate: workout,
            hour: 7,
            minute: 30,
            now: now,
            calendar: calendar
        )

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder!)
        let workoutDay = calendar.dateComponents([.year, .month, .day], from: workout)
        #expect(components.year == workoutDay.year)
        #expect(components.month == workoutDay.month)
        #expect(components.day == workoutDay.day)
        #expect(components.hour == 7)
        #expect(components.minute == 30)
    }

    @Test("Past training-day reminders are not scheduled")
    func noPastReminder() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 9))!
        let sameDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12))!

        let reminder = NotificationSchedulePolicy.workoutReminderDate(
            workoutDate: sameDay,
            hour: 8,
            minute: 0,
            now: now,
            calendar: calendar
        )
        #expect(reminder == nil)
    }

    @Test("Feedback reminder targets 30 minutes after completion")
    func feedbackDelay() {
        let completed = Date(timeIntervalSince1970: 1_800_000_000)
        let now = completed.addingTimeInterval(60)
        let reminder = NotificationSchedulePolicy.feedbackReminderDate(completedAt: completed, now: now)

        #expect(reminder == completed.addingTimeInterval(30 * 60))
    }

    @Test("Old history does not generate feedback reminders")
    func noHistoricalFeedbackReminder() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let completed = now.addingTimeInterval(-13 * 60 * 60)
        #expect(NotificationSchedulePolicy.feedbackReminderDate(completedAt: completed, now: now) == nil)
    }
}
