import Foundation
import WorkoutKit

/// Schedules TriLoop workouts into Apple's Workout app.
///
/// §5: TriLoop does not replace the Workout app. It hands over a structured
/// workout and later reads the result back from HealthKit.
struct WorkoutKitScheduler: WorkoutScheduling {
    var calendar: Calendar = .current

    var isSupported: Bool {
        WorkoutScheduler.isSupported
    }

    func authorizationState() async -> WorkoutSchedulingAuthorization {
        await Self.map(WorkoutScheduler.shared.authorizationState)
    }

    func requestAuthorization() async -> WorkoutSchedulingAuthorization {
        Self.map(await WorkoutScheduler.shared.requestAuthorization())
    }

    func schedule(_ workout: PlannedWorkout, at date: Date) async throws {
        guard WorkoutScheduler.isSupported else {
            throw WorkoutSchedulingError.unavailable
        }
        guard let plan = WorkoutPlanBuilder.plan(for: workout) else {
            throw WorkoutSchedulingError.unsupportedWorkout
        }
        guard await requestAuthorization() == .authorized else {
            throw WorkoutSchedulingError.notAuthorized
        }

        // WorkoutKit identifies a scheduled workout by plan *and* date, so the
        // components must include the time, not just the day.
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        await WorkoutScheduler.shared.schedule(plan, at: components)

        // `schedule` neither throws nor returns anything, so the only way to know
        // it worked is to read the schedule back.
        guard await scheduledWorkoutIDs().contains(plan.id) else {
            throw WorkoutSchedulingError.notAccepted
        }
    }

    func scheduledWorkouts() async -> [ScheduledWorkoutSummary] {
        await WorkoutScheduler.shared.scheduledWorkouts.map { entry in
            ScheduledWorkoutSummary(
                id: entry.plan.id,
                displayName: Self.displayName(of: entry.plan),
                date: calendar.date(from: entry.date),
                isComplete: entry.complete
            )
        }
    }

    private static func displayName(of plan: WorkoutPlan) -> String? {
        if case .custom(let custom) = plan.workout {
            return custom.displayName
        }
        return nil
    }

    private static func map(
        _ state: WorkoutScheduler.AuthorizationState
    ) -> WorkoutSchedulingAuthorization {
        switch state {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .notDetermined
        }
    }
}
