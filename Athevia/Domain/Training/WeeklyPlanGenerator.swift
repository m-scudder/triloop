import Foundation

/// Builds the next week from the previous one plus its analysis.
///
/// Deterministic and side-effect free: it returns a new `WeeklyPlan` and leaves
/// the previous one untouched. Persisting the result is the caller's job.
struct WeeklyPlanGenerator: Sendable {
    /// When the athlete can train. Supplied from their stored setup; the
    /// fallback opens every day so tests and previews about progression do not
    /// have to describe a schedule.
    var schedule: AthleteSchedule = .everyDay()
    /// Which sports the athlete selected. Availability is the scheduling
    /// ceiling. Current capability and sport-specific safety decide how many
    /// days carry training; unused availability is rest, never fake recovery.
    var preferences: [SportPreference] = []
    /// Per-sport primary workout goal. Missing legacy values default to distance.
    var prescriptionBases: [Sport: WorkoutPrescriptionBasis] = [:]
    /// Desired weekly training frequency. Availability remains only the pool of
    /// days the planner may place those sessions on.
    var targetTrainingDays: Int = 3
    var frequencyPolicy = WeeklyTrainingFrequencyPolicy()
    var planner: WeekShapePlanner = WeekShapePlanner()
    /// Optional event journey context supplied by PlanStore. Safety analysis
    /// remains authoritative; this only redistributes non-recovery slots.
    var journey: TrainingJourney?
    var objective: TrainingObjective?
    var capability: AthleteCapabilityAssessment?
    var openWaterConsent: OpenWaterTrainingConsent = .unavailable
    var eventState: AthleteEventState = .upcoming
    var prescriptionBuilder = PhaseWorkoutPrescriptionBuilder()
    var calendar: Calendar = .current

    func generate(after plan: WeeklyPlan, analysis: WeeklyAnalysis) -> WeeklyPlan {
        let start = calendar.startOfDay(
            for: calendar.date(
                byAdding: .day,
                value: 1,
                to: plan.endDate
            ) ?? plan.endDate
        )

        func day(_ offset: Int) -> Date {
            calendar.date(
                byAdding: .day,
                value: offset,
                to: start
            ) ?? start
        }

        let adjusted = analysis.sports.reduce(plan.parameters) { current, sport in
            current.applying(sport.adjustment, to: sport.sport)
        }
        let evidenceAdjusted = applyingSustainedEvidenceProgression(
            adjusted,
            previous: plan.parameters,
            analysis: analysis
        )
        let parameters = evidenceAdjusted
            .fillingTrainingWindow(minutes: trainingMinuteCap(in: schedule))

        // A sport sent to recovery is not prescribed next week. Its intended
        // slots are left open so they become recovery sessions rather than
        // being reassigned as extra load to another sport.
        let recovering = Set(
            analysis.sports
                .filter { $0.status == .recoveryRequired }
                .map(\.sport)
        )

        let intendedFrequencies: [SportFrequency]
        let selectedSports = Sport.allCases.filter { sport in
            preferences.first(where: { $0.sport == sport })?.isTrained == true
        }
        let weeklyTarget = frequencyPolicy.nextTarget(
            requested: targetTrainingDays,
            selectedSportCount: selectedSports.count,
            availableDays: schedule.availableDays.count,
            previousPlan: plan,
            analysis: analysis
        )

        if selectedSports.isEmpty {
            // Legacy/tests without stored preferences retain the previous
            // prescribed sport counts rather than guessing a new mix.
            intendedFrequencies = Sport.allCases.compactMap { sport in
                let count = plan.prescribedTrainingSessions
                    .count { $0.discipline.sport == sport }
                return count > 0 ? SportFrequency(sport: sport, sessions: count) : nil
            }
        } else if let capability {
            intendedFrequencies = WeekShapePlanner.frequencies(
                for: selectedSports,
                schedule: schedule,
                capability: capability,
                priorities: journey?.sportPriorities ?? [],
                sessionLimit: weeklyTarget
            )
        } else if let journey {
            intendedFrequencies = WeekShapePlanner.frequencies(
                for: selectedSports,
                schedule: schedule,
                priorities: journey.sportPriorities,
                sessionLimit: weeklyTarget
            )
        } else {
            intendedFrequencies = WeekShapePlanner.frequencies(
                for: selectedSports,
                schedule: schedule,
                sessionLimit: weeklyTarget
            )
        }

        let frequencies = intendedFrequencies.filter {
            !recovering.contains($0.sport)
        }

        let shape = planner.plan(
            schedule: schedule,
            frequencies: frequencies,
            durations: durations(from: parameters)
        )

        // Recovery is intentional: only a sport explicitly held back by the
        // previous week's safety analysis creates recovery days. Ordinary
        // unused availability remains rest.
        let recoveryDays: Set<Weekday> = recovering.isEmpty
            ? []
            : Set(
                Weekday.trainingWeek.compactMap { weekday in
                    guard schedule.isAvailable(on: weekday),
                          !shape.disciplines[
                            weekday.offsetFromMonday
                          ].isTrainingSession else {
                        return nil
                    }
                    return weekday
                }
            )

        if let journey, journey.eventResolutionRequired || journey.requiresNextObjective {
            let workouts = (0..<7).compactMap { offset -> PlannedWorkout? in
                let date = day(offset)
                guard let weekday = Weekday(
                    date: date,
                    calendar: calendar
                ) else {
                    return nil
                }

                if schedule.isAvailable(on: weekday) {
                    return PrescribedSessions.recoveryDay(
                        on: date,
                        goal: journey.eventResolutionRequired
                            ? "Resolve the event outcome before Athevia starts another training block."
                            : "Choose your next objective before Athevia starts another training block."
                    )
                }
                return PrescribedSessions.restDay(on: date)
            }
            return WeeklyPlan(
                weekNumber: plan.weekNumber + 1,
                startDate: start,
                endDate: day(6),
                status: .active,
                generationReason: journey.eventResolutionRequired
                    ? "Training held until the event outcome is resolved."
                    : "Training held until the next objective is chosen.",
                generationReasonCode: .profileChanged,
                parameters: parameters,
                workouts: workouts
            )
        }

        var workouts: [PlannedWorkout] = []
        var sportOrdinals: [Sport: Int] = [:]
        let multisport = MultisportTrainingPolicy()
        let brickEligible = journey.map {
            multisport.canScheduleBrick(
                journey: $0,
                objective: objective ?? .init(kind: .generalFitness),
                schedule: schedule,
                recoveringSports: recovering
            )
        } ?? false
        let brickAllowedByCurrentRecovery = capability?.recoveryState != .needsAttention
            && capability?.recoveryState != .recovering
        let nextWeekNumber = plan.weekNumber + 1
        let simulationEligible = journey.map {
            multisport.canScheduleRaceSimulation(
                journey: $0,
                objective: objective ?? .init(kind: .generalFitness),
                capability: capability,
                nextWeekNumber: nextWeekNumber,
                recoveringSports: recovering
            )
        } ?? false
        var brickPlaced = false

        for offset in 0..<7 {
            let date = day(offset)
            guard let weekday = Weekday(
                date: date,
                calendar: calendar
            ) else {
                continue
            }
            let discipline = shape.disciplines[
                weekday.offsetFromMonday
            ]

            // Event Day replaces whatever the weekly shape would otherwise put
            // on the date, including a recovery slot.
            if let event = objective?.event,
               eventState.status == .upcoming,
               let eventDate = event.eventDate,
               calendar.isDate(date, inSameDayAs: eventDate) {
                workouts.append(EventDayPrescription.workout(for: event, on: date))
                continue
            }

            guard let sport = discipline.sport else {
                workouts.append(
                    recoveryDays.contains(weekday)
                        ? PrescribedSessions.recoveryDay(
                            on: date,
                            goal: recoveryGoal(for: recovering)
                        )
                        : PrescribedSessions.restDay(
                            on: date,
                            reason: schedule.isAvailable(on: weekday)
                                ? "No workout is needed on this available day."
                                : "No workout is scheduled because you marked this day unavailable."
                            )
                )
                continue
            }

            let ordinal = sportOrdinals[sport, default: 0]
            sportOrdinals[sport] = ordinal + 1

            if sport == .cycling,
               brickEligible,
               brickAllowedByCurrentRecovery,
               !brickPlaced {
                let brick: PlannedWorkout
                if simulationEligible {
                    brick = MultisportPrescribedSessions.raceSimulation(
                        on: date,
                        parameters: parameters,
                        prescription: multisport.raceSimulation(parameters: parameters)
                    )
                } else {
                    brick = MultisportPrescribedSessions.brick(
                        on: date,
                        parameters: parameters,
                        prescription: multisport.brick(parameters: parameters)
                    )
                }
                WorkoutPrescriptionBasisAdapter.applyMultisport(
                    brick,
                    bases: prescriptionBases,
                    capability: capability
                )
                workouts.append(brick)
                brickPlaced = true
            } else {
                workouts.append(
                    prescriptionBuilder.workout(
                        sport: sport,
                        on: date,
                        parameters: parameters,
                        journey: journey,
                        objective: objective,
                        capability: capability,
                        openWaterConsent: openWaterConsent,
                        sportOrdinal: ordinal,
                        prescriptionBasis: prescriptionBases[sport, default: .distance]
                    )
                )
            }
        }

        if let phase = journey?.phase {
            let multiplier = multisport.workloadMultiplier(for: phase)
            if multiplier < 1 {
                workouts
                    .filter { workout in
                        // Single-sport prescriptions already apply phase volume
                        // before basis conversion. Only bricks need this second
                        // whole-workout phase scaling pass.
                        guard workout.discipline == .multisport else { return false }
                        guard let eventDate = objective?.event?.eventDate else { return true }
                        return !calendar.isDate(workout.date, inSameDayAs: eventDate)
                    }
                    .forEach {
                        MultisportPrescribedSessions.tapered($0, multiplier: multiplier)
                    }
            }
        }

        let frequencyReason = frequencyPolicy.explanation(
            requested: targetTrainingDays,
            actual: workouts.filter { $0.discipline.isTrainingSession }.count,
            previousActual: plan.prescribedTrainingSessions.count,
            analysis: analysis
        )

        return WeeklyPlan(
            weekNumber: plan.weekNumber + 1,
            startDate: start,
            endDate: day(6),
            status: .active,
            generationReason: reason(from: analysis, parameters: parameters) + " " + frequencyReason,
            generationReasonCode: PlanGenerationReason.from(analysis.sports.map(\.status)),
            parameters: parameters,
            workouts: workouts
        )
    }

    /// A single successful ride already earns the sport engine's normal
    /// five-minute step. Once recent history shows sustained, well-tolerated
    /// cycling, use demonstrated duration to avoid weeks of tiny catch-up.
    ///
    /// This is intentionally cycling-specific: running impact and swimming
    /// technique need their own progression rules. Safety/weekly analysis must
    /// still say progress before historical evidence can accelerate anything.
    private func applyingSustainedEvidenceProgression(
        _ parameters: TrainingParameters,
        previous: TrainingParameters,
        analysis: WeeklyAnalysis
    ) -> TrainingParameters {
        guard let capability,
              capability.recoveryState == .stable,
              capability.recentMissedOrSkippedSessions == 0,
              (capability.recentAdherence ?? 0) >= 0.85,
              capability.recentCompletedSessions >= 6,
              let cycling = analysis.analysis(for: .cycling),
              cycling.status == .progress,
              cycling.completedEverySession,
              cycling.highestPain <= 1,
              (cycling.averageRPE ?? 10) <= 5 else {
            return parameters
        }

        let demonstrated = capability.cycling.bestRecentDurationSeconds
        guard demonstrated > 0 else { return parameters }

        var next = parameters
        // HealthKit duration is total ride time, while rideWorkSeconds excludes
        // warm-up/cooldown. Translate like-for-like before using it as evidence.
        let demonstratedWork = max(
            demonstrated - previous.rideWarmUpSeconds - previous.rideCooldownSeconds,
            TrainingParameters.Limits.minimumRideWorkSeconds
        )

        // Meaningful but bounded adaptation: sustained evidence may advance at
        // most ten work minutes in one generated week. The normal engine has
        // already supplied a five-minute increase.
        let evidenceTarget = min(
            demonstratedWork,
            previous.rideWorkSeconds + 10 * 60
        )
        next.rideWorkSeconds = max(next.rideWorkSeconds, evidenceTarget)
        return next
    }

    private func recoveryGoal(for recovering: Set<Sport>) -> String? {
        guard let sport = recovering.sorted(by: { $0.rawValue < $1.rawValue }).first else { return nil }
        return "Replacing \(sport.displayName.lowercased()) while last week's symptoms settle."
    }

    private func durations(from parameters: TrainingParameters) -> [Sport: TimeInterval] {
        let reference = Date.now

        return Sport.allCases.reduce(into: [:]) { totals, sport in
            totals[sport] = PrescribedSessions
                .session(sport.discipline, on: reference, parameters: parameters)
                .estimatedDurationSeconds ?? 0
        }
    }

    /// New onboarding stores one daily limit. For older profiles with mixed per-day limits, use the largest window here;
    /// placement still validates every individual day's limit.
    private func trainingMinuteCap(in schedule: AthleteSchedule) -> Int? {
        schedule.availableDays.compactMap(\.maxDurationMinutes).max()
    }

    private func reason(from analysis: WeeklyAnalysis, parameters: TrainingParameters) -> String {
        var analysisReason = analysis.sports.isEmpty
            ? "Repeat of the previous week."
            : analysis.sports
                .map { "\($0.sport.displayName): \($0.status.displayName.lowercased()) — \($0.adjustment.summary.lowercased())." }
                .joined(separator: " ")

        if let capability,
           let cycling = analysis.analysis(for: .cycling),
           cycling.status == .progress,
           capability.recentCompletedSessions >= 6,
           capability.cycling.bestRecentDurationSeconds > 0,
           parameters.rideWorkSeconds >= capability.cycling.prescribedWorkSeconds + 10 * 60 {
            analysisReason += " Cycling also advanced from your recent completed-ride evidence, not only the last ride."
        }

        guard let availableMinutes = schedule.availableDays.compactMap(\.maxDurationMinutes).max() else {
            return analysisReason
        }

        let longestPlannedMinutes = durations(from: parameters)
            .values
            .map { Int(($0 / 60).rounded()) }
            .max() ?? availableMinutes

        guard longestPlannedMinutes < availableMinutes else { return analysisReason }
        return analysisReason + " You selected \(availableMinutes) minutes per training day. That time is an upper limit, not a target; capability, recovery needs and training phase may make sessions shorter."
    }
}
