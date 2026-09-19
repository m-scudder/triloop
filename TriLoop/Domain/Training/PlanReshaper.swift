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
        let workoutID: UUID
        let date: Date
        let discipline: Discipline
        let skipped: Bool
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
        guard plan.status != .completed,
              calendar.startOfDay(for: plan.endDate) >= boundary else {
            return Outcome(preserved: plan.workouts.count)
        }
        let movable = plan.orderedWorkouts.filter {
            $0.discipline.isTrainingSession && canEdit($0, in: plan, asOf: now)
        }

        guard !movable.isEmpty else {
            return Outcome(preserved: plan.orderedWorkouts.count)
        }

        let movableIDs = Set(movable.map(\.id))
        let fixed = plan.workouts.filter {
            !movableIDs.contains($0.id) && ($0.discipline != .rest || !isUnrecorded($0))
        }
        let remaining = AthleteSchedule(
            days: Weekday.trainingWeek.map { weekday in
                var updated = schedule.availability(on: weekday)
                guard let date = date(for: weekday, in: plan), date >= boundary,
                      !fixed.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) else {
                    updated.isAvailable = false
                    return updated
                }
                return updated
            }
        )

        let shape = planner.plan(
            schedule: remaining,
            frequencies: Sport.allCases.map { sport in
                SportFrequency(sport: sport, sessions: movable.filter { $0.discipline.sport == sport }.count)
            },
            durations: Sport.allCases.reduce(into: [:]) { durations, sport in
                durations[sport] = movable.filter { $0.discipline.sport == sport }
                    .compactMap(\.estimatedDurationSeconds).max() ?? 0
            }
        )

        var placements: [UUID: Date] = [:]
        var changes: [Change] = []
        var dropped = 0
        for workout in movable {
            let candidates = Weekday.trainingWeek.filter {
                shape.disciplines[$0.offsetFromMonday] == workout.discipline
            }.compactMap { date(for: $0, in: plan) }.sorted { left, right in
                let original = calendar.startOfDay(for: workout.date)
                if left == original { return true }
                if right == original { return false }
                return left < right
            }
            let target = candidates.first { candidate in
                (try? validatePlacement(
                    workout, on: candidate, in: plan, schedule: schedule,
                    excluding: movableIDs, placements: placements, asOf: now
                )) != nil
            }
            if let target {
                placements[workout.id] = target
                if !calendar.isDate(target, inSameDayAs: workout.date) {
                    changes.append(Change(workoutID: workout.id, date: target,
                                          discipline: workout.discipline, skipped: false))
                }
            } else {
                dropped += 1
                changes.append(Change(workoutID: workout.id, date: workout.date,
                                      discipline: workout.discipline, skipped: true))
            }
        }

        return Outcome(
            changes: changes,
            preserved: plan.orderedWorkouts.count - movable.count,
            dropped: dropped
        )
    }

    enum Failure: Error, LocalizedError, Equatable {
        case historyIsImmutable
        case workoutIsImmutable
        case dateOutsidePlan
        case pastDate
        case occupiedDay
        case unavailableDay
        case durationDoesNotFit
        case recoveryRequired
        case recoverySpacing
        case missingSchedule
        case useSingleWorkoutMove

        var errorDescription: String? {
            switch self {
            case .historyIsImmutable: "This week is closed or in the past. Its schedule cannot change."
            case .workoutIsImmutable: "Only an uncompleted, planned workout from today onward can change."
            case .dateOutsidePlan: "Choose a date within this training week."
            case .pastDate: "Choose today or a future day."
            case .occupiedDay: "This day already holds a session. Choose another day."
            case .unavailableDay: "This weekday is marked unavailable in your recurring schedule."
            case .durationDoesNotFit: "The total training time does not fit this day's availability."
            case .recoveryRequired: "Recovery is required. This training cannot be scheduled."
            case .recoverySpacing: "This move would remove required spacing between running sessions."
            case .missingSchedule: "Set your training availability before changing the schedule."
            case .useSingleWorkoutMove: "Move one workout at a time. Whole-week shifting is no longer supported."
            }
        }
    }

    func isUnrecorded(_ workout: PlannedWorkout) -> Bool {
        workout.status == .planned && workout.feedback == nil
            && workout.importedSummary == nil && workout.completedAt == nil
            && workout.recoveryCheckIn == nil
    }

    func canEdit(_ workout: PlannedWorkout, in plan: WeeklyPlan, asOf now: Date = .now) -> Bool {
        plan.status != .completed && plan.workouts.contains { $0.id == workout.id }
            && calendar.startOfDay(for: plan.endDate) >= calendar.startOfDay(for: now)
            && plan.contains(calendar.startOfDay(for: workout.date), calendar: calendar)
            && calendar.startOfDay(for: workout.date) >= calendar.startOfDay(for: now)
            && isUnrecorded(workout)
    }

    func validateWeek(_ plan: WeeklyPlan, on date: Date, asOf now: Date = .now) throws {
        let day = calendar.startOfDay(for: date)
        guard plan.status != .completed,
              calendar.startOfDay(for: plan.endDate) >= calendar.startOfDay(for: now)
        else { throw Failure.historyIsImmutable }
        guard plan.contains(day, calendar: calendar) else { throw Failure.dateOutsidePlan }
        guard day >= calendar.startOfDay(for: now) else { throw Failure.pastDate }
    }

    func validatePlacement(
        _ workout: PlannedWorkout,
        on date: Date,
        in plan: WeeklyPlan,
        schedule: AthleteSchedule,
        excluding excluded: Set<UUID> = [],
        placements: [UUID: Date] = [:],
        allowingAlongside: Bool = false,
        asOf now: Date = .now
    ) throws {
        try validateWeek(plan, on: date, asOf: now)
        guard let weekday = Weekday(date: date, calendar: calendar) else { throw Failure.dateOutsidePlan }
        let availability = schedule.availability(on: weekday)
        guard availability.isAvailable else { throw Failure.unavailableDay }
        let others = plan.workouts.filter {
            $0.id != workout.id && (!excluded.contains($0.id) || placements[$0.id] != nil)
        }
        let sameDay = others.filter {
            calendar.isDate(placements[$0.id] ?? $0.date, inSameDayAs: date)
        }
        guard !sameDay.contains(where: { $0.discipline == .recovery }) else { throw Failure.recoveryRequired }
        let sessions = sameDay.filter { $0.discipline.isTrainingSession && !$0.isSkipped }
        guard allowingAlongside || sessions.isEmpty else { throw Failure.occupiedDay }
        let durations = (sessions + [workout]).map(\.estimatedDurationSeconds)
        if availability.maxDurationMinutes != nil {
            guard durations.allSatisfy({ $0 != nil && $0!.isFinite && $0! > 0 }),
                  availability.accommodates(seconds: durations.compactMap { $0 }.reduce(0, +))
            else { throw Failure.durationDoesNotFit }
        }
        for recorded in plan.trainingSessions {
            guard let feedback = recorded.feedback else { continue }
            if case .requiresRecovery = TrainingSafetyPolicy().evaluate(
                FeedbackSummary(feedback), recovery: recorded.recoveryCheckIn.map(RecoverySummary.init)
            ) { throw Failure.recoveryRequired }
        }
        if let sport = workout.discipline.sport, planner.highImpact.contains(sport) {
            let tooClose = others.contains { other in
                guard other.discipline.sport == sport, !other.isSkipped else { return false }
                let otherDate = placements[other.id] ?? other.date
                // An explicit "alongside" choice is intentional stacking, so
                // same-day work must not be rejected by the between-day spacing
                // rule. Adjacent-day protection still applies normally.
                if allowingAlongside && calendar.isDate(otherDate, inSameDayAs: date) {
                    return false
                }
                let distance = calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: date),
                    to: calendar.startOfDay(for: otherDate)
                ).day ?? 0
                return abs(distance) < 2
            }
            guard !tooClose else { throw Failure.recoverySpacing }
        }
    }

    private func date(for weekday: Weekday, in plan: WeeklyPlan) -> Date? {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: plan.startDate) }
            .first { Weekday(date: $0, calendar: calendar) == weekday && plan.contains($0, calendar: calendar) }
            .map { calendar.startOfDay(for: $0) }
    }
}
