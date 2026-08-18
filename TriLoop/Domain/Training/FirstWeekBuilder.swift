import Foundation

/// Builds the athlete's first week from what onboarding collected.
///
/// Separate from `WeeklyPlanGenerator` because it has no previous week to
/// progress from: everything comes from the assessment, once. Deterministic and
/// free of persistence, so the same answers always give the same first week.
struct FirstWeekBuilder: Sendable {
    var resolver: any StartingParameterResolving = StartingParameterResolver()
    var planner: WeekShapePlanner = WeekShapePlanner()
    var calendar: Calendar = .current

    enum BuildFailure: Error, Equatable {
        /// Too few days, or no sport available on any of them.
        case scheduleUnusable
        /// Days are available but nothing could be placed on them.
        case noSessionsFit
    }

    /// - Parameters:
    ///   - startDate: the first day of the plan. Need not be a Monday: starting
    ///     mid-week produces a short first week that still ends on the Sunday,
    ///     so every following week is a full Monday-to-Sunday one.
    ///   - weekNumber: where this sits in the athlete's history. Not always 1:
    ///     an existing athlete completing setup gets their next week, never a
    ///     second week one.
    func build(
        setup: AthleteSetup,
        poolLengthMeters: Double,
        startDate: Date = .now,
        weekNumber: Int = 1
    ) throws -> WeeklyPlan {
        guard setup.canGeneratePlan else { throw BuildFailure.scheduleUnusable }

        let parameters = resolver.resolve(
            baseline: setup.baseline,
            goal: setup.goal,
            poolLengthMeters: poolLengthMeters
        )

        let start = calendar.startOfDay(for: startDate)
        let firstWeekday = Weekday(date: start, calendar: calendar) ?? .monday
        let remainingDays = 6 - firstWeekday.offsetFromMonday

        let shape = planner.plan(
            schedule: setup.schedule,
            frequencies: WeekShapePlanner.frequencies(from: setup.preferences, schedule: setup.schedule),
            durations: durations(from: parameters, preferences: setup.preferences)
        )

        guard shape.isViable else { throw BuildFailure.noSessionsFit }

        // Indexed by weekday, not by position, so a short week still puts each
        // sport on the day the athlete said they could train it.
        let workouts = (0...remainingDays).compactMap { offset -> PlannedWorkout? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                  let weekday = Weekday(date: date, calendar: calendar) else { return nil }

            return WorkoutTemplates.session(
                shape.disciplines[weekday.offsetFromMonday],
                on: date,
                parameters: parameters
            )
        }

        return WeeklyPlan(
            weekNumber: weekNumber,
            startDate: start,
            endDate: calendar.date(byAdding: .day, value: remainingDays, to: start) ?? start,
            status: .active,
            generationReason: reason(for: setup, shape: shape),
            generationReasonCode: .initialAssessment,
            parameters: parameters,
            workouts: workouts
        )
    }

    /// How long a session is expected to run, so a day too short for it is not
    /// offered. The athlete's stated length wins where it is longer than the
    /// prescription, since that is the time they actually need to set aside.
    private func durations(
        from parameters: TrainingParameters,
        preferences: [SportPreference]
    ) -> [Sport: TimeInterval] {
        let reference = Date.now

        return Sport.allCases.reduce(into: [:]) { totals, sport in
            let prescribed = WorkoutTemplates
                .session(sport.discipline, on: reference, parameters: parameters)
                .estimatedDurationSeconds ?? 0
            let stated = preferences.first { $0.sport == sport }?.typicalSeconds ?? 0
            totals[sport] = max(prescribed, stated)
        }
    }

    private func reason(for setup: AthleteSetup, shape: WeekShape) -> String {
        let sports = shape.disciplines
            .compactMap(\.sport)
            .reduce(into: [Sport: Int]()) { counts, sport in counts[sport, default: 0] += 1 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value) × \($0.key.displayName.lowercased())" }
            .joined(separator: ", ")

        let opening = "Built from your \(setup.goal.displayName.lowercased()) goal and what you can do today"
        guard !sports.isEmpty else { return opening + "." }

        let unfitted = shape.fittedEverything
            ? ""
            : " Some sessions did not fit your availability and were left out."

        return "\(opening): \(sports). Starting conservatively so TriLoop can learn how you respond.\(unfitted)"
    }
}
