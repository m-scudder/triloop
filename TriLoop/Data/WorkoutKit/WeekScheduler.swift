import Foundation
import WorkoutKit

/// Schedules a whole week to Apple Watch in one action.
///
/// Per-workout scheduling means opening each session in turn, which is more
/// effort than the week is worth. This is idempotent: sessions already on the
/// Watch are left alone, so it can be run repeatedly and on every launch.
@MainActor
struct WeekScheduler {
    var scheduler: any WorkoutScheduling = WorkoutKitScheduler()
    var calendar: Calendar = .current

    struct Outcome: Equatable, Sendable {
        var added: Int = 0
        var alreadyScheduled: Int = 0
        var failed: Int = 0

        var changedAnything: Bool { added > 0 }
    }

    func scheduleWeek(_ plan: WeeklyPlan, now: Date = .now) async -> Outcome {
        guard scheduler.isSupported else { return Outcome() }

        let today = calendar.startOfDay(for: now)
        let existing = await scheduler.scheduledWorkoutIDs()
        var outcome = Outcome()

        // WorkoutKit caps how many workouts can be queued at once.
        var remaining = max(WorkoutScheduler.maxAllowedScheduledWorkoutCount - existing.count, 0)

        for workout in plan.trainingSessions {
            // Nothing is gained by queuing a session whose day has gone, or one
            // already reported on.
            guard calendar.startOfDay(for: workout.date) >= today, !workout.isCompleted else { continue }

            if existing.contains(workout.id) {
                outcome.alreadyScheduled += 1
                continue
            }
            guard remaining > 0 else { break }

            do {
                try await scheduler.schedule(workout, at: workout.suggestedScheduleDate(now: now, calendar: calendar))
                outcome.added += 1
                remaining -= 1
            } catch {
                outcome.failed += 1
            }
        }

        return outcome
    }
}
