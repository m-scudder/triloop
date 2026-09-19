import Foundation
import SwiftData
@preconcurrency import UserNotifications

enum TrainingNotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .authorized
        @unknown default: self = .denied
        }
    }
}

enum TrainingNotificationRoute: String, Sendable {
    case home
    case plan
}

/// Notification taps can arrive before SwiftUI has constructed RootView, and
/// account/onboarding can delay the tab hierarchy even further. Persist the
/// requested destination until the app is actually ready to consume it.
enum TrainingNotificationRouteStore {
    private static let pendingKey = "pendingTrainingNotificationRoute"

    static func enqueue(
        _ route: TrainingNotificationRoute,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(route.rawValue, forKey: pendingKey)
    }

    static func consume(
        defaults: UserDefaults = .standard
    ) -> TrainingNotificationRoute? {
        guard let raw = defaults.string(forKey: pendingKey),
              let route = TrainingNotificationRoute(rawValue: raw) else {
            defaults.removeObject(forKey: pendingKey)
            return nil
        }

        defaults.removeObject(forKey: pendingKey)
        return route
    }
}

enum TrainingNotificationPreferences {
    static let enabledKey = "trainingNotificationsEnabled"
    static let workoutRemindersKey = "workoutRemindersEnabled"
    static let feedbackRemindersKey = "feedbackRemindersEnabled"
    static let planReadyKey = "planReadyNotificationsEnabled"
    static let promptDismissedKey = "notificationPromptDismissed"
    static let reminderHourKey = "trainingReminderHour"
    static let reminderMinuteKey = "trainingReminderMinute"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var workoutReminders: Bool { UserDefaults.standard.bool(forKey: workoutRemindersKey) }
    static var feedbackReminders: Bool { UserDefaults.standard.bool(forKey: feedbackRemindersKey) }
    static var planReady: Bool { UserDefaults.standard.bool(forKey: planReadyKey) }

    static var reminderHour: Int {
        UserDefaults.standard.object(forKey: reminderHourKey) as? Int ?? 8
    }

    static var reminderMinute: Int {
        UserDefaults.standard.object(forKey: reminderMinuteKey) as? Int ?? 0
    }

    static func enableDefaults(hour: Int, minute: Int) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: enabledKey)
        defaults.set(true, forKey: workoutRemindersKey)
        defaults.set(true, forKey: feedbackRemindersKey)
        defaults.set(true, forKey: planReadyKey)
        defaults.set(hour, forKey: reminderHourKey)
        defaults.set(minute, forKey: reminderMinuteKey)
        defaults.set(true, forKey: promptDismissedKey)
    }
}

struct TrainingNotificationWorkout: Sendable, Equatable {
    let id: UUID
    let date: Date
    let title: String
    let discipline: Discipline
    let durationSeconds: TimeInterval?
    let status: PlannedWorkoutStatus
    let hasFeedback: Bool
    let completedAt: Date?

    @MainActor
    init(_ workout: PlannedWorkout) {
        id = workout.id
        date = workout.date
        title = workout.title
        discipline = workout.discipline
        durationSeconds = workout.prescribedDurationSeconds ?? workout.estimatedDurationSeconds
        status = workout.status
        hasFeedback = workout.feedback != nil
        completedAt = workout.completedAt ?? workout.importedSummary?.endDate
    }
}

struct NotificationSchedulePolicy {
    static func workoutReminderDate(
        workoutDate: Date,
        hour: Int,
        minute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: workoutDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components), date > now else { return nil }
        return date
    }

    static func feedbackReminderDate(completedAt: Date, now: Date = .now) -> Date? {
        // Do not resurrect reminders for old history when notifications are enabled.
        guard completedAt >= now.addingTimeInterval(-12 * 60 * 60) else { return nil }
        return max(completedAt.addingTimeInterval(30 * 60), now.addingTimeInterval(5))
    }
}

private final class TrainingNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = TrainingNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo["route"] as? String
        guard let raw, let route = TrainingNotificationRoute(rawValue: raw) else { return }

        // Do not mutate SwiftUI navigation from the notification callback.
        // On a cold launch this callback can beat RootView to the screen.
        TrainingNotificationRouteStore.enqueue(route)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The user is already looking at TriLoop; avoid a banner over the app.
        [.badge, .sound]
    }
}

@MainActor
final class TrainingNotificationManager {
    static let shared = TrainingNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let ownedPrefixes = ["triloop.workout.", "triloop.feedback.", "triloop.plan."]

    private init() {
        center.delegate = TrainingNotificationDelegate.shared
    }

    func authorizationStatus() async -> TrainingNotificationAuthorization {
        TrainingNotificationAuthorization(await center.notificationSettings().authorizationStatus)
    }

    @discardableResult
    func requestAuthorization(hour: Int, minute: Int) async -> TrainingNotificationAuthorization {
        let before = await authorizationStatus()
        if before == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let after = await authorizationStatus()
        if after == .authorized {
            TrainingNotificationPreferences.enableDefaults(hour: hour, minute: minute)
        }
        return after
    }

    func synchronize(plans: [WeeklyPlan], now: Date = .now) async {
        let workouts = plans.flatMap(\.orderedWorkouts).map(TrainingNotificationWorkout.init)
        await synchronize(workouts: workouts, now: now)
    }

    func synchronize(workouts: [TrainingNotificationWorkout], now: Date = .now) async {
        guard TrainingNotificationPreferences.enabled,
              await authorizationStatus() == .authorized else {
            await removeAllOwnedPendingRequests()
            return
        }

        let pending = await center.pendingNotificationRequests()
        var pendingIDs = Set(pending.map(\.identifier))
        let validWorkoutIDs = Set(workouts.map { workoutIdentifier($0.id) })
        let validFeedbackIDs = Set(workouts.map { feedbackIdentifier($0.id) })

        // Remove reminders whose workout moved, was skipped/completed, or no longer exists.
        let staleWorkoutIDs = pending.compactMap { request -> String? in
            guard request.identifier.hasPrefix("triloop.workout.") else { return nil }
            return validWorkoutIDs.contains(request.identifier) ? request.identifier : request.identifier
        }
        if !staleWorkoutIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleWorkoutIDs)
            pendingIDs.subtract(staleWorkoutIDs)
        }

        // Rebuild workout reminders so a moved session always gets the new date.
        if TrainingNotificationPreferences.workoutReminders {
            let existingWorkoutIDs = pendingIDs.filter { $0.hasPrefix("triloop.workout.") }
            center.removePendingNotificationRequests(withIdentifiers: Array(existingWorkoutIDs))
            pendingIDs.subtract(existingWorkoutIDs)

            for workout in workouts where workout.discipline.isTrainingSession && workout.status == .planned {
                guard let fireDate = NotificationSchedulePolicy.workoutReminderDate(
                    workoutDate: workout.date,
                    hour: TrainingNotificationPreferences.reminderHour,
                    minute: TrainingNotificationPreferences.reminderMinute,
                    now: now
                ) else { continue }
                await scheduleWorkoutReminder(workout, at: fireDate)
            }
        } else {
            let ids = pendingIDs.filter { $0.hasPrefix("triloop.workout.") }
            center.removePendingNotificationRequests(withIdentifiers: Array(ids))
            pendingIDs.subtract(ids)
        }

        // Feedback reminders are one-shot. Keep an existing one rather than pushing
        // it another 30 minutes every time the app foregrounds.
        for workout in workouts {
            let id = feedbackIdentifier(workout.id)
            if workout.hasFeedback || workout.status != .completed {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                pendingIDs.remove(id)
                continue
            }
            guard TrainingNotificationPreferences.feedbackReminders,
                  !pendingIDs.contains(id),
                  let completedAt = workout.completedAt,
                  let fireDate = NotificationSchedulePolicy.feedbackReminderDate(completedAt: completedAt, now: now)
            else { continue }
            await scheduleFeedbackReminder(workout, at: fireDate)
            pendingIDs.insert(id)
        }

        let obsoleteFeedback = pendingIDs.filter {
            $0.hasPrefix("triloop.feedback.") && !validFeedbackIDs.contains($0)
        }
        center.removePendingNotificationRequests(withIdentifiers: Array(obsoleteFeedback))
    }

    func notifyPlanReady(_ plan: WeeklyPlan) async {
        guard TrainingNotificationPreferences.enabled,
              TrainingNotificationPreferences.planReady,
              await authorizationStatus() == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Next week is ready"
        content.body = "Your training has been adjusted using this week's sessions."
        content.sound = .default
        content.userInfo = ["route": TrainingNotificationRoute.plan.rawValue]

        let request = UNNotificationRequest(
            identifier: "triloop.plan.\(plan.weekNumber)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try? await center.add(request)
    }

    func cancelFeedbackReminder(for workoutID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [feedbackIdentifier(workoutID)])
    }

    private func scheduleWorkoutReminder(_ workout: TrainingNotificationWorkout, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = workout.title
        var parts: [String] = [workout.discipline.displayName]
        if let duration = workout.durationSeconds {
            parts.append(TrainingFormatter.totalDuration(seconds: duration))
        }
        content.body = parts.joined(separator: " · ") + ". Open TriLoop when you're ready."
        content.sound = .default
        content.userInfo = ["route": TrainingNotificationRoute.home.rawValue]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let request = UNNotificationRequest(
            identifier: workoutIdentifier(workout.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    private func scheduleFeedbackReminder(_ workout: TrainingNotificationWorkout, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "How did that \(workout.discipline.displayName.lowercased()) feel?"
        content.body = "Add your report so TriLoop can adapt what comes next."
        content.sound = .default
        content.userInfo = ["route": TrainingNotificationRoute.home.rawValue]

        let delay = max(date.timeIntervalSinceNow, 1)
        let request = UNNotificationRequest(
            identifier: feedbackIdentifier(workout.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        try? await center.add(request)
    }

    private func removeAllOwnedPendingRequests() async {
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { id in ownedPrefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func workoutIdentifier(_ id: UUID) -> String { "triloop.workout.\(id.uuidString)" }
    private func feedbackIdentifier(_ id: UUID) -> String { "triloop.feedback.\(id.uuidString)" }
}
