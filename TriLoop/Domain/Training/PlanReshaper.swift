import Foundation

/// Works out how an existing week should change when availability does.
///
/// Decides only: what to change and to what. Applying it is the store's job,
/// which keeps this deterministic and testable without persistence.
///
/// History is never rewritten. A session that has been reported on, skipped, or
/// whose day has already passed is left exactly where it is — the plan is a
/// record of what happened as much as an instruction for what is next.
struct PlanReshaper: Sendable {
    var planner: WeekShapePlanner = WeekShapePlanner()
    var calendar: Calendar = .current

    struct Change: Equatable, Sendable {
        let date: Date
        let discipline: Discipline
    }

    struct Outcome: Equatable, Sendable {
        var changes: [Change] = []
        /// Sessions left alone because they are already resolved or in the past.
        var preserved: Int = 0
        /// Sessions that no longer fit anywhere in the remaining days.
        var dropped: Int = 0

        var isUnchanged: Bool { changes.isEmpty }
    }

    func reshape(
        _ plan: WeeklyPlan,
        schedule: AthleteSchedule,
        preferences: [SportPreference],
        asOf now: Date = .now
    ) -> Outcome {
        let boundary = calendar.startOfDay(for: now)

        let movable = plan.orderedWorkouts.filter { workout in
            calendar.startOfDay(for: workout.date) >= boundary
                && !workout.hasReport
                && !workout.isSkipped
        }

        guard !movable.isEmpty else {
            return Outcome(preserved: plan.orderedWorkouts.count)
        }

        let movableWeekdays = Set(movable.compactMap { Weekday(date: $0.date, calendar: calendar) })

        // Only the days still in play are offered; everything else keeps what it
        // already has, whether that is a completed session or a past rest day.
        let remaining = AthleteSchedule(
            days: schedule.days.map { day in
                var updated = day
                if !movableWeekdays.contains(day.weekday) { updated.isAvailable = false }
                return updated
            }
        )

        let shape = planner.plan(
            schedule: remaining,
            frequencies: frequencies(for: movable, preferences: preferences, schedule: remaining),
            durations: durations(from: plan.parameters, preferences: preferences)
        )

        let changes = movable.compactMap { workout -> Change? in
            guard let weekday = Weekday(date: workout.date, calendar: calendar) else { return nil }
            let target = shape.disciplines[weekday.offsetFromMonday]
            guard target != workout.discipline else { return nil }
            return Change(date: workout.date, discipline: target)
        }

        return Outcome(
            changes: changes,
            preserved: plan.orderedWorkouts.count - movable.count,
            dropped: shape.unplaced.values.reduce(0, +)
        )
    }

    /// What the week still owes.
    ///
    /// Taken from the sessions actually left rather than from the athlete's
    /// weekly preference, so reshaping mid-week never quietly adds work to a
    /// week that has already had some of it done.
    private func frequencies(
        for movable: [PlannedWorkout],
        preferences: [SportPreference],
        schedule: AthleteSchedule
    ) -> [SportFrequency] {
        let days = schedule.availableDays.count

        return Sport.allCases.compactMap { sport in
            let outstanding = movable.filter { $0.discipline.sport == sport }.count
            guard outstanding > 0, days > 0 else { return nil }
            return SportFrequency(sport: sport, sessions: min(outstanding, days))
        }
    }

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
}
