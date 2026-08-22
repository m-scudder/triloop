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
    ///   - startDate: the first day the athlete will train. The plan still runs
    ///     Monday to Sunday — days before this become rest — so every week in
    ///     the app has the same shape.
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
        let monday = calendar.date(byAdding: .day, value: -firstWeekday.offsetFromMonday, to: start) ?? start

        // Both the ask and the placement use the days that are left, so a
        // partial first week is simply smaller rather than reported as a week
        // that failed to fit.
        let available = remaining(setup.schedule, from: firstWeekday)

        let shape = planner.plan(
            schedule: available,
            frequencies: WeekShapePlanner.frequencies(from: setup.preferences, schedule: available),
            durations: durations(from: parameters, preferences: setup.preferences)
        )

        guard shape.isViable else { throw BuildFailure.noSessionsFit }

        let workouts = Weekday.trainingWeek.compactMap { weekday -> PlannedWorkout? in
            guard let date = calendar.date(byAdding: .day, value: weekday.offsetFromMonday, to: monday) else {
                return nil
            }
            // Days already gone by the time setup finished are rest, not a
            // session the athlete silently failed to do.
            let discipline = weekday < firstWeekday ? Discipline.rest : shape.disciplines[weekday.offsetFromMonday]
            return PrescribedSessions.session(discipline, on: date, parameters: parameters)
        }

        return WeeklyPlan(
            weekNumber: weekNumber,
            startDate: monday,
            endDate: calendar.date(byAdding: .day, value: 6, to: monday) ?? monday,
            status: .active,
            generationReason: reason(for: setup, shape: shape),
            generationReasonCode: .initialAssessment,
            parameters: parameters,
            workouts: workouts
        )
    }

    /// The schedule with elapsed days closed off, so every session the athlete
    /// asked for is placed in the part of the week they still have.
    private func remaining(_ schedule: AthleteSchedule, from weekday: Weekday) -> AthleteSchedule {
        AthleteSchedule(
            days: schedule.days.map { day in
                var updated = day
                if day.weekday < weekday { updated.isAvailable = false }
                return updated
            }
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
            let prescribed = PrescribedSessions
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
