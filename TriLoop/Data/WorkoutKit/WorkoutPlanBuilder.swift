import Foundation
import HealthKit
import WorkoutKit

/// Converts TriLoop's prescription into a WorkoutKit workout.
///
/// `WorkoutKit.WorkoutStep` is qualified throughout: TriLoop has its own
/// `WorkoutStep` model, and inside this module the local type wins.
enum WorkoutPlanBuilder {

    static func plan(for workout: PlannedWorkout) -> WorkoutPlan? {
        customWorkout(for: workout).map { WorkoutPlan(.custom($0), id: workout.id) }
    }

    static func customWorkout(for workout: PlannedWorkout) -> CustomWorkout? {
        guard let sport = workout.discipline.sport else { return nil }

        let activity = sport.workoutActivityType
        guard CustomWorkout.supportsActivity(activity) else { return nil }

        var warmup: WorkoutKit.WorkoutStep?
        var cooldown: WorkoutKit.WorkoutStep?
        var blocks: [IntervalBlock] = []

        for step in workout.orderedSteps {
            switch step.kind {
            case .warmUp:
                warmup = convert(step)

            case .cooldown:
                cooldown = convert(step)

            case .repeatBlock:
                let children = step.orderedChildren.map {
                    IntervalStep($0.purpose, step: convert($0))
                }
                guard !children.isEmpty else { continue }
                blocks.append(
                    IntervalBlock(steps: children, iterations: max(step.repeatCount ?? 1, 1))
                )

            case .work, .recovery:
                blocks.append(
                    IntervalBlock(steps: [IntervalStep(step.purpose, step: convert(step))], iterations: 1)
                )
            }
        }

        guard warmup != nil || cooldown != nil || !blocks.isEmpty else { return nil }

        return CustomWorkout(
            activity: activity,
            location: sport.workoutLocation,
            displayName: workout.title,
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown
        )
    }

    private static func convert(_ step: WorkoutStep) -> WorkoutKit.WorkoutStep {
        WorkoutKit.WorkoutStep(goal: goal(for: step), displayName: step.title)
    }

    /// Duration wins over distance: every TriLoop step that has both is
    /// prescribed by time, and a step with neither is athlete-paced.
    private static func goal(for step: WorkoutStep) -> WorkoutGoal {
        if let seconds = step.durationSeconds {
            return .time(seconds, .seconds)
        }
        if let meters = step.distanceMeters {
            return .distance(meters, .meters)
        }
        return .open
    }
}

private extension WorkoutStep {
    var purpose: IntervalStep.Purpose {
        kind == .recovery ? .recovery : .work
    }
}

extension Sport {
    var workoutActivityType: HKWorkoutActivityType {
        switch self {
        case .running: .running
        case .swimming: .swimming
        case .cycling: .cycling
        }
    }

    /// Swimming defaults to a pool; the outdoor sports are recorded outdoors so
    /// the Watch enables GPS.
    var workoutLocation: HKWorkoutSessionLocationType {
        switch self {
        case .swimming: .indoor
        case .running, .cycling: .outdoor
        }
    }
}

extension PlannedWorkout {
    /// WorkoutKit schedules against a wall-clock time, but TriLoop prescribes a
    /// day rather than an hour. Morning is the default; a session scheduled for
    /// today that has already passed that hour moves to shortly from now.
    func suggestedScheduleDate(
        now: Date = .now,
        preferredHour: Int = 7,
        calendar: Calendar = .current
    ) -> Date {
        let morning = calendar.date(
            bySettingHour: preferredHour, minute: 0, second: 0, of: date
        ) ?? date

        guard morning > now else {
            return now.addingTimeInterval(10 * 60)
        }
        return morning
    }
}
