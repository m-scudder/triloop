import Foundation

/// The shape of a training week, Monday first.
///
/// Held as data so the weekly rhythm can change later without touching the
/// generator: swapping a rest day for a second ride is an edit to this array.
struct WeeklySchedule: Equatable, Sendable {
    var disciplines: [Discipline]

    /// Sessions are spaced so the two runs and two swims never sit back to back.
    static let beginner = WeeklySchedule(
        disciplines: [.running, .swimming, .recovery, .running, .swimming, .cycling, .rest]
    )
}

/// Builds the next week from the previous one plus its analysis.
///
/// Deterministic and side-effect free: it returns a new `WeeklyPlan` and leaves
/// the previous one untouched. Persisting the result is the caller's job.
struct WeeklyPlanGenerator: Sendable {
    var schedule: WeeklySchedule = .beginner
    var calendar: Calendar = .current

    func generate(after plan: WeeklyPlan, analysis: WeeklyAnalysis) -> WeeklyPlan {
        let monday = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: plan.endDate) ?? plan.endDate
        )

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        }

        let parameters = analysis.sports.reduce(plan.parameters) { current, sport in
            current.applying(sport.adjustment, to: sport.sport)
        }

        // A sport sent to recovery is not prescribed at all next week; its slot
        // becomes a recovery day rather than a lighter version of the session.
        let recovering = Set(
            analysis.sports
                .filter { $0.status == .recoveryRequired }
                .map(\.sport)
        )

        var workouts: [PlannedWorkout] = []

        for (offset, discipline) in schedule.disciplines.enumerated() {
            let date = day(offset)

            guard let sport = discipline.sport else {
                workouts.append(
                    discipline == .recovery
                        ? WorkoutTemplates.recoveryDay(on: date)
                        : WorkoutTemplates.restDay(on: date)
                )
                continue
            }

            if recovering.contains(sport) {
                workouts.append(
                    WorkoutTemplates.recoveryDay(
                        on: date,
                        goal: "Replacing \(sport.displayName.lowercased()) while last week's symptoms settle."
                    )
                )
                continue
            }

            switch sport {
            case .running:
                workouts.append(
                    WorkoutTemplates.runWalk(on: date, parameters: parameters)
                )
            case .swimming:
                workouts.append(
                    WorkoutTemplates.techniqueSwim(on: date, parameters: parameters)
                )
            case .cycling:
                workouts.append(
                    WorkoutTemplates.easyRide(on: date, parameters: parameters)
                )
            }
        }

        return WeeklyPlan(
            weekNumber: plan.weekNumber + 1,
            startDate: monday,
            endDate: day(schedule.disciplines.count - 1),
            status: .active,
            generationReason: reason(from: analysis),
            parameters: parameters,
            workouts: workouts
        )
    }

    private func reason(from analysis: WeeklyAnalysis) -> String {
        guard !analysis.sports.isEmpty else {
            return "Repeat of the previous week."
        }

        return analysis.sports
            .map { "\($0.sport.displayName): \($0.status.displayName.lowercased()) — \($0.adjustment.summary.lowercased())." }
            .joined(separator: " ")
    }
}
