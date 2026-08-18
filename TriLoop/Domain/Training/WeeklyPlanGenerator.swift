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
    /// How much of each sport the athlete asked for. Used when the previous
    /// week cannot say — after a recovery week there is nothing to carry
    /// forward, and without this training would never resume.
    var preferences: [SportPreference] = []
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

            let carried = plan.trainingSessions.filter { $0.discipline.sport == sport }.count
            let intended = carried > 0
                ? carried
                : preferences.first { $0.sport == sport }?.sessionsPerWeek ?? 0

            guard intended > 0, days > 0 else { return nil }
            return SportFrequency(sport: sport, sessions: min(intended, days))
        }

        let shape = planner.plan(
            schedule: schedule,
            frequencies: frequencies,
            durations: durations(from: parameters)
        )

        // One recovery day for each session actually pulled. Turning every free
        // day into recovery would bury the week in it, and a week with nothing
        // to report cannot be closed.
        let pulled = recovering.reduce(0) { total, sport in
            total + plan.trainingSessions.filter { $0.discipline.sport == sport }.count
        }
        let recoveryDays = freeDays(in: shape, limit: pulled)

        var workouts: [PlannedWorkout] = []

        for (offset, discipline) in shape.disciplines.enumerated() {
            let date = day(offset)

            guard let sport = discipline.sport else {
                workouts.append(
                    recoveryDays.contains(offset)
                        ? WorkoutTemplates.recoveryDay(on: date, goal: recoveryGoal(for: recovering))
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

    /// Positions of the first `limit` days the planner left empty, earliest
    /// first so the result never depends on iteration order.
    private func freeDays(in shape: WeekShape, limit: Int) -> Set<Int> {
        guard limit > 0 else { return [] }

        let free = shape.disciplines.enumerated()
            .filter { !$0.element.isTrainingSession }
            .map(\.offset)

        return Set(free.prefix(limit))
    }

    private func recoveryGoal(for recovering: Set<Sport>) -> String? {
        guard let sport = recovering.sorted(by: { $0.rawValue < $1.rawValue }).first else { return nil }
        return "Replacing \(sport.displayName.lowercased()) while last week's symptoms settle."
    }

    private func durations(from parameters: TrainingParameters) -> [Sport: TimeInterval] {
        let reference = Date.now
        return Sport.allCases.reduce(into: [:]) { totals, sport in
            let prescribed = WorkoutTemplates
                .session(sport.discipline, on: reference, parameters: parameters)
                .estimatedDurationSeconds ?? 0
            let stated = preferences.first { $0.sport == sport }?.typicalSeconds ?? 0
            totals[sport] = max(prescribed, stated)
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
