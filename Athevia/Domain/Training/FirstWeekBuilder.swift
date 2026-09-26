import Foundation

/// Builds the athlete's first week from what onboarding collected.
///
/// Separate from `WeeklyPlanGenerator` because it has no previous week to
/// progress from: everything comes from the assessment, once. Deterministic and
/// free of persistence, so the same answers always give the same first week.
struct FirstWeekBuilder: Sendable {
    var resolver: any StartingParameterResolving = StartingParameterResolver()
    var planner: WeekShapePlanner = WeekShapePlanner()
    var capabilityBuilder = AthleteCapabilityAssessmentBuilder()
    var prescriptionBuilder = PhaseWorkoutPrescriptionBuilder()
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

        let start = calendar.startOfDay(for: startDate)
        let firstWeekday = Weekday(date: start, calendar: calendar) ?? .monday
        let monday = calendar.date(byAdding: .day, value: -firstWeekday.offsetFromMonday, to: start) ?? start

        // Both the ask and the placement use the days that are left, so a
        // partial first week is simply smaller rather than reported as a week
        // that failed to fit.
        let available = remaining(setup.schedule, from: firstWeekday)

        let parameters = resolver.resolve(
            baseline: setup.baseline,
            goal: setup.goal,
            poolLengthMeters: poolLengthMeters
        )
        .capped(toTrainingMinutes: trainingMinuteCap(in: available))

        let selectedSports = setup.preferences.filter(\.isTrained).map(\.sport)
        let capability = capabilityBuilder.build(
            setup: setup,
            plans: [],
            asOf: startDate,
            startingParameters: parameters
        )
        let journey = TrainingJourneyPlanner(calendar: calendar).plan(
            setup: setup,
            capability: capability,
            asOf: startDate
        )
        let frequencies = WeekShapePlanner.frequencies(
            for: selectedSports,
            schedule: available,
            baseline: setup.baseline,
            priorities: setup.objective.kind == .event ? journey.sportPriorities : []
        )

        let shape = planner.plan(
            schedule: available,
            frequencies: frequencies,
            durations: durations(from: parameters)
        )

        guard shape.isViable else { throw BuildFailure.noSessionsFit }

        var workouts: [PlannedWorkout] = []
        var sportOrdinals: [Sport: Int] = [:]
        let multisport = MultisportTrainingPolicy()
        let brickEligible = multisport.canScheduleBrick(
            journey: journey,
            objective: setup.objective,
            schedule: available
        )
        let brickAllowedByCurrentRecovery = capability.recoveryState == .stable
        let simulationEligible = multisport.canScheduleRaceSimulation(
            journey: journey,
            objective: setup.objective,
            capability: capability,
            nextWeekNumber: weekNumber,
            recoveringSports: []
        )
        var brickPlaced = false

        for weekday in Weekday.trainingWeek {
            guard let date = calendar.date(
                byAdding: .day,
                value: weekday.offsetFromMonday,
                to: monday
            ) else {
                continue
            }

            // Event Day is a lifecycle fact, not another training slot. It must
            // replace normal training even when the week shape would otherwise
            // have left this date as recovery.
            if weekday >= firstWeekday,
               let event = setup.objective.event,
               setup.eventState.status == .upcoming,
               let eventDate = event.eventDate,
               calendar.isDate(date, inSameDayAs: eventDate) {
                workouts.append(EventDayPrescription.workout(for: event, on: date))
                continue
            }

            // Days already gone by the time setup finished are rest, not a
            // session the athlete silently failed to do. An available day that
            // does not need training is also rest; Recovery is prescribed only
            // when the training model has an actual recovery reason.
            if weekday < firstWeekday {
                workouts.append(PrescribedSessions.restDay(on: date))
                continue
            }

            let discipline = shape.disciplines[weekday.offsetFromMonday]
            guard let sport = discipline.sport else {
                workouts.append(PrescribedSessions.restDay(on: date))
                continue
            }

            let ordinal = sportOrdinals[sport, default: 0]
            sportOrdinals[sport] = ordinal + 1

            if sport == .cycling,
               brickEligible,
               brickAllowedByCurrentRecovery,
               !brickPlaced {
                if simulationEligible {
                    workouts.append(
                        MultisportPrescribedSessions.raceSimulation(
                            on: date,
                            parameters: parameters,
                            prescription: multisport.raceSimulation(parameters: parameters)
                        )
                    )
                } else {
                    workouts.append(
                        MultisportPrescribedSessions.brick(
                            on: date,
                            parameters: parameters,
                            prescription: multisport.brick(parameters: parameters)
                        )
                    )
                }
                brickPlaced = true
            } else {
                workouts.append(
                    prescriptionBuilder.workout(
                        sport: sport,
                        on: date,
                        parameters: parameters,
                        journey: journey,
                        objective: setup.objective,
                        capability: capability,
                        openWaterConsent: setup.openWaterTrainingConsent,
                        sportOrdinal: ordinal
                    )
                )
            }
        }

        let multiplier = multisport.workloadMultiplier(for: journey.phase)
        if multiplier < 1 {
            workouts
                .filter { workout in
                    guard workout.discipline.isTrainingSession else { return false }
                    guard let eventDate = setup.objective.event?.eventDate else { return true }
                    return !calendar.isDate(workout.date, inSameDayAs: eventDate)
                }
                .forEach {
                    MultisportPrescribedSessions.tapered($0, multiplier: multiplier)
                }
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

    /// How long the generated session actually runs. The old per-sport
    /// "typical duration" value no longer overrides the single daily time
    /// answer collected during onboarding.
    private func durations(from parameters: TrainingParameters) -> [Sport: TimeInterval] {
        let reference = Date.now

        return Sport.allCases.reduce(into: [:]) { totals, sport in
            totals[sport] = PrescribedSessions
                .session(sport.discipline, on: reference, parameters: parameters)
                .estimatedDurationSeconds ?? 0
        }
    }

    /// New onboarding uses one time limit for every training day. Using the largest available window preserves the athlete's capability-based
    /// prescription; the week-shape planner then places that session only on days
    /// whose individual time limit can actually accommodate it.
    private func trainingMinuteCap(in schedule: AthleteSchedule) -> Int? {
        schedule.availableDays.compactMap(\.maxDurationMinutes).max()
    }

    private func reason(for setup: AthleteSetup, shape: WeekShape) -> String {
        let sports = shape.disciplines
            .compactMap(\.sport)
            .reduce(into: [Sport: Int]()) { counts, sport in counts[sport, default: 0] += 1 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value) × \($0.key.displayName.lowercased())" }
            .joined(separator: ", ")

        let opening = "Built from your \(setup.objective.displayName.lowercased()) goal and what you can do today"
        guard !sports.isEmpty else { return opening + "." }

        let selectedMinutes = setup.schedule.availableDays.compactMap(\.maxDurationMinutes).max()
        let plannedMinutes = shape.disciplines
            .compactMap(\.sport)
            .compactMap { durations(from: setup.parametersFallback(poolLengthMeters: 25))[$0] }
            .map { Int(($0 / 60).rounded()) }
            .max()
        let timeExplanation: String
        if let selectedMinutes, let plannedMinutes, plannedMinutes < selectedMinutes {
            timeExplanation = " You gave Athevia up to \(selectedMinutes) minutes; this week deliberately uses shorter sessions because your current starting point does not need the full window yet."
        } else {
            timeExplanation = ""
        }

        let unfitted = shape.fittedEverything
            ? ""
            : " Some sessions did not fit your availability and were left out."

        return "\(opening): \(sports). Starting conservatively so Athevia can learn how you respond.\(timeExplanation)\(unfitted)"
    }
}
