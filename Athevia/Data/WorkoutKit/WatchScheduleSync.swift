import Foundation
import SwiftData

/// Keeps the Watch in step with the week after the plan changes.
///
/// One entry point, because scheduling used to live only inside Today: adding a
/// workout from the library left the Watch holding the old week until the
/// athlete happened to open that tab.
@MainActor
enum WatchScheduleSync {
    // MainActor methods can interleave at awaits. Queue whole reconciliations so
    // foreground and plan-change triggers cannot both replace the same entry.
    private static var pending: Task<WeekScheduler.Outcome, Never>?
    private static var pendingID: UUID?

    /// Read directly rather than through `@AppStorage`, so this can be called
    /// from anywhere that changes the plan.
    static var isEnabledByPreference: Bool {
        UserDefaults.standard.object(forKey: "automaticallyScheduleWorkouts") as? Bool ?? true
    }

    /// Never prompts. Scheduling stays silent until permission has been granted
    /// through an explicit action.
    @discardableResult
    static func sync(
        _ plan: WeeklyPlan?,
        scheduler: any WorkoutScheduling = WorkoutKitScheduler(),
        now: Date = .now
    ) async -> WeekScheduler.Outcome {
        guard let plan, isEnabledByPreference else { return WeekScheduler.Outcome() }
        let previous = pending
        let id = UUID()
        let task = Task { @MainActor in
            if let previous { _ = await previous.value }
            guard isEnabledByPreference,
                  await scheduler.authorizationState() == .authorized else {
                return WeekScheduler.Outcome()
            }
            return await WeekScheduler(scheduler: scheduler).scheduleWeek(plan, now: now)
        }
        pending = task
        pendingID = id
        let outcome = await task.value
        if pendingID == id {
            pending = nil
            pendingID = nil
        }
        return outcome
    }
}
