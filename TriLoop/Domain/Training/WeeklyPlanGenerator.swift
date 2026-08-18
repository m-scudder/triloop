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
    /// When the athlete can train. Supplied from their stored setup; the
    /// fallback opens every day so tests and previews about progression do not
    /// have to describe a schedule.
    var schedule: AthleteSchedule = .everyDay()
    var planner: WeekShapePlanner = WeekShapePlanner()
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

        // Frequency carries forward from what the athlete was already doing, so
        // availability changes the placement of sessions and never their number.
        let days = schedule.availableDays.count
        let frequencies = Sport.allCases.compactMap { sport -> SportFrequency? in
            guard !recovering.contains(sport) else { return nil }
            let count = plan.trainingSessions.filter { $0.discipline.sport == sport }.count
            guard count > 0, days > 0 else { return nil }
            return SportFrequency(sport: sport, sessions: min(count, days))
        }

        let shape = planner.plan(
            schedule: schedule,
            frequencies: frequencies,
            durations: durations(from: parameters)
        )

        var workouts: [PlannedWorkout] = []

        for (offset, discipline) in shape.disciplines.enumerated() {
            let date = day(offset)

            guard let sport = discipline.sport else {
                // A rest day becomes recovery when a sport was pulled for it, so
                // the week still shows why the session is missing.
                let replaced = recovering.isEmpty ? Discipline.rest : .recovery
                workouts.append(
                    replaced == .recovery
                        ? WorkoutTemplates.recoveryDay(
                            on: date,
                            goal: recovering
                                .sorted { $0.rawValue < $1.rawValue }
                                .first
                                .map { "Replacing \($0.displayName.lowercased()) while last week's symptoms settle." }
                        )
                        : WorkoutTemplates.restDay(on: date)
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
            endDate: day(6),
            status: .active,
            generationReason: reason(from: analysis),
            generationReasonCode: PlanGenerationReason.from(analysis.sports.map(\.status)),
            parameters: parameters,
            workouts: workouts
        )
    }

    private func durations(from parameters: TrainingParameters) -> [Sport: TimeInterval] {
        let reference = Date.now
        return Sport.allCases.reduce(into: [:]) { totals, sport in
            totals[sport] = WorkoutTemplates
                .session(sport.discipline, on: reference, parameters: parameters)
                .estimatedDurationSeconds
        }
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
