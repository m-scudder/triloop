import Foundation
import SwiftData

/// Turns a reusable template into one scheduled occurrence.
///
/// §10.2.8: the result is an ordinary `PlannedWorkout`, so Plan, Today, Workout
/// Detail, WorkoutKit, matching, feedback and analysis all treat it exactly as
/// they treat a generated session. The only difference it carries is where it
/// came from.
@MainActor
enum WorkoutTemplateScheduler {

    /// What is already on the chosen day.
    enum Conflict: Equatable {
        case none
        /// A session that can be added alongside or replaced.
        case session(workoutID: UUID, title: String)
        /// A session already trained. §10.3.15: history is not rewritten.
        case completedSession(workoutID: UUID, title: String)
    }

    enum Resolution: Equatable {
        case alongside
        case replace
    }

    enum Failure: Error, Equatable {
        case dateOutsidePlan
        /// Replacing was asked for, but the day holds work already done.
        case cannotReplaceCompletedSession
    }

    static func conflict(
        on date: Date,
        in plan: WeeklyPlan,
        calendar: Calendar = .current
    ) -> Conflict {
        let day = calendar.startOfDay(for: date)
        let sessions = plan.trainingSessions.filter {
            calendar.isDate($0.date, inSameDayAs: day)
        }

        if let completed = sessions.first(where: { $0.isCompleted || $0.hasReport }) {
            return .completedSession(workoutID: completed.id, title: completed.title)
        }
        if let session = sessions.first {
            return .session(workoutID: session.id, title: session.title)
        }
        return .none
    }

    /// The workout a template produces, with its own resolved prescription.
    ///
    /// Steps are materialised fresh, so the template can be edited or deleted
    /// afterwards without touching this occurrence.
    static func workout(
        from template: WorkoutTemplate,
        on date: Date,
        calendar: Calendar = .current
    ) -> PlannedWorkout {
        PlannedWorkout(
            date: calendar.startOfDay(for: date),
            discipline: template.sport.discipline,
            title: template.name,
            goal: template.purpose,
            targetRPE: template.targetRPE,
            prescribedDurationSeconds: template.totalDurationSeconds,
            targetDistanceMeters: template.totalDistanceMeters,
            origin: template.source == .triLoop ? .library : .custom,
            steps: template.structure.makeSteps()
        )
    }

    @discardableResult
    static func add(
        _ template: WorkoutTemplate,
        to plan: WeeklyPlan,
        on date: Date,
        resolving resolution: Resolution = .alongside,
        calendar: Calendar = .current
    ) throws -> PlannedWorkout {
        let day = calendar.startOfDay(for: date)
        guard day >= calendar.startOfDay(for: plan.startDate),
              day <= calendar.startOfDay(for: plan.endDate)
        else { throw Failure.dateOutsidePlan }

        let existing = conflict(on: day, in: plan, calendar: calendar)

        if resolution == .replace {
            guard case .session(let workoutID, _) = existing else {
                throw Failure.cannotReplaceCompletedSession
            }
            remove(workoutID, from: plan)
        }

        let workout = workout(from: template, on: day, calendar: calendar)
        plan.modelContext?.insert(workout)
        plan.workouts.append(workout)

        // A rest day is a placeholder, not training. Adding a session to one
        // should leave the day holding the session rather than both.
        removeRestDay(on: day, from: plan, calendar: calendar)

        return workout
    }

    /// Detaches the workout from the plan, then deletes it.
    ///
    /// Both are needed: deleting alone leaves the relationship holding the
    /// object until the next save, and detaching alone orphans a row. The
    /// context is captured first because detaching clears it.
    private static func remove(_ workoutID: UUID, from plan: WeeklyPlan) {
        guard let workout = plan.workouts.first(where: { $0.id == workoutID }) else { return }

        let context = workout.modelContext
        plan.workouts.removeAll { $0.id == workoutID }
        context?.delete(workout)
    }

    private static func removeRestDay(on day: Date, from plan: WeeklyPlan, calendar: Calendar) {
        let rest = plan.workouts.filter {
            $0.discipline == .rest && calendar.isDate($0.date, inSameDayAs: day)
        }
        for workout in rest { remove(workout.id, from: plan) }
    }
}
