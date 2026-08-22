import Foundation
import HealthKit
import WorkoutKit

/// Converts TriLoop's prescription into a WorkoutKit workout.
///
/// `WorkoutKit.WorkoutStep` is qualified throughout: TriLoop has its own
/// `WorkoutStep` model, and inside this module the local type wins.
/// Whether a workout can be sent to Apple Watch, and why not when it cannot.
///
/// §10.3.18: the builder must not offer to send something the adapter would
/// quietly drop.
enum WorkoutKitCompatibility: Equatable, Sendable {
    case supported
    case unsupported(reason: String)

    var isSupported: Bool { self == .supported }

    var reason: String? {
        switch self {
        case .supported: nil
        case .unsupported(let reason): reason
        }
    }
}

extension WorkoutPlanBuilder {
    /// Answered by running the real conversion, so the check cannot disagree
    /// with what sending would actually do.
    static func compatibility(for template: WorkoutTemplate) -> WorkoutKitCompatibility {
        guard CustomWorkout.supportsActivity(template.sport.workoutActivityType) else {
            return .unsupported(
                reason: "Apple Watch does not support custom \(template.sport.displayName.lowercased()) workouts."
            )
        }

        let workout = PlannedWorkout(
            date: .now,
            discipline: template.sport.discipline,
            title: template.name,
            steps: template.structure.makeSteps()
        )

        guard customWorkout(for: workout) != nil else {
            return .unsupported(
                reason: "This workout has no step Apple Watch can follow."
            )
        }
        return .supported
    }
}

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
            displayName: displayName(for: workout),
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown
        )
    }

    /// Marked so the athlete can pick TriLoop's session out of a Watch list
    /// that also holds Apple's built-in workouts and any other app's.
    private static func displayName(for workout: PlannedWorkout) -> String {
        "TriLoop · \(workout.title)"
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
