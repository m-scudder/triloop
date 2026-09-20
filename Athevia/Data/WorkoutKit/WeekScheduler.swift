import Foundation
import WorkoutKit

/// Schedules a whole week to Apple Watch in one action.
///
/// Per-workout scheduling means opening each session in turn, which is more
/// effort than the week is worth. Unchanged sessions are left alone, while
/// renamed sessions are replaced without changing their scheduled time.
@MainActor
struct WeekScheduler {
    var scheduler: any WorkoutScheduling = WorkoutKitScheduler()
    var calendar: Calendar = .current

    struct Outcome: Equatable, Sendable {
        var added: Int = 0
        var alreadyScheduled: Int = 0
        var failed: Int = 0
        var removed: Int = 0

        var changedAnything: Bool { added > 0 || removed > 0 }
    }

    func scheduleWeek(_ plan: WeeklyPlan, now: Date = .now) async -> Outcome {
        guard scheduler.isSupported else { return Outcome() }

        let today = calendar.startOfDay(for: now)
        var outcome = Outcome()

        let wanted = plan.trainingSessions.filter {
            // Nothing is gained by queuing a session whose day has gone, or one
            // already dealt with.
            calendar.startOfDay(for: $0.date) >= today && !$0.isCompleted && !$0.isSkipped
        }

        // Anything else the Watch is still holding is spent: yesterday's
        // session, one already reported, or a leftover from a week that has
        // since been regenerated. Left alone it accumulates until the athlete
        // cannot find today's workout.
        let entries = await scheduler.scheduledWorkouts()
        let existing = Set(entries.map(\.id))
        let stale = existing.subtracting(wanted.map(\.id))
        if !stale.isEmpty {
            await scheduler.removeScheduled(ids: stale)
            outcome.removed = stale.count
        }

        // WorkoutKit caps how many workouts can be queued at once.
        var remaining = max(
            WorkoutScheduler.maxAllowedScheduledWorkoutCount - (existing.count - stale.count),
            0
        )

        for workout in wanted {
            let matching = entries.filter { $0.id == workout.id }
            // A completed Watch workout may still be waiting for Health to sync.
            // Renaming must never replace it with an uncompleted session.
            if matching.contains(where: \.isComplete) {
                outcome.alreadyScheduled += 1
                continue
            }
            if !matching.isEmpty,
               matching.allSatisfy({ $0.displayName == WorkoutPlanBuilder.displayName(for: workout) }) {
                outcome.alreadyScheduled += 1
                continue
            }

            if !matching.isEmpty {
                await scheduler.removeScheduled(ids: [workout.id])
                outcome.removed += 1
                remaining += 1
            }
            guard remaining > 0 else { break }

            do {
                let date = matching.first?.date
                    ?? workout.suggestedScheduleDate(now: now, calendar: calendar)
                try await scheduler.schedule(workout, at: date)
                outcome.added += 1
                remaining -= 1
            } catch {
                outcome.failed += 1
            }
        }

        return outcome
    }
}
