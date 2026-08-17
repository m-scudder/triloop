import Foundation

/// The shape of a training week, Monday first.
struct WeeklySchedule: Equatable, Sendable {
    var disciplines: [Discipline]

    /// Once all three sports are in play. No recovery days: the volumes are low
    /// enough that a rest day on Sunday is the only break needed.
    static let allSports = WeeklySchedule(
        disciplines: [.running, .swimming, .cycling, .running, .swimming, .cycling, .rest]
    )

    /// Before swimming starts. Running carries the first half of the week and
    /// riding the second, which is when the bike is available.
    static let runAndRide = WeeklySchedule(
        disciplines: [.running, .running, .running, .running, .cycling, .cycling, .rest]
    )

    /// Picks a shape for the week and drops any sport not yet available, falling
    /// back to running since it needs no equipment.
    static func forWeek(
        starting monday: Date,
        availability: SportAvailability = .athlete(),
        calendar: Calendar = .current
    ) -> WeeklySchedule {
        let swimmingAvailable = availability.isAvailable(.swimming, on: monday, calendar: calendar)
        let base = swimmingAvailable ? allSports : runAndRide

        let adjusted = base.disciplines.enumerated().map { offset, discipline -> Discipline in
            guard let sport = discipline.sport else { return discipline }
            let day = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            guard availability.isAvailable(sport, on: day, calendar: calendar) else {
                return .running
            }
            return discipline
        }

        return WeeklySchedule(disciplines: adjusted)
    }
}

/// Builds the next week from the previous one plus its analysis.
///
/// Deterministic and side-effect free: it returns a new `WeeklyPlan` and leaves
/// the previous one untouched. Persisting the result is the caller's job.
struct WeeklyPlanGenerator: Sendable {
    var availability: SportAvailability = .athlete()
    var calendar: Calendar = .current

    func generate(after plan: WeeklyPlan, analysis: WeeklyAnalysis) -> WeeklyPlan {
        let monday = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: plan.endDate) ?? plan.endDate
        )
        let schedule = WeeklySchedule.forWeek(
            starting: monday,
            availability: availability,
            calendar: calendar
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
