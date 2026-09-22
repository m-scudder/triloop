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
    /// Which sports the athlete selected. Session counts are no longer treated
    /// as quotas; availability defines the week's plan slots.
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

        let adjusted = analysis.sports.reduce(plan.parameters) { current, sport in
            current.applying(sport.adjustment, to: sport.sport)
        }
        let parameters = adjusted.capped(
            toTrainingMinutes: trainingMinuteCap(in: schedule)
        )

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

        if selectedSports.isEmpty {
            // Legacy/tests without stored preferences retain the previous
            // prescribed sport counts rather than guessing a new mix.
            intendedFrequencies = Sport.allCases.compactMap { sport in
                let count = plan.prescribedTrainingSessions
                    .count { $0.discipline.sport == sport }
                return count > 0 ? SportFrequency(sport: sport, sessions: count) : nil
            }
        } else {
            intendedFrequencies = WeekShapePlanner.frequencies(
                for: selectedSports,
                schedule: schedule
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

        // Every day the athlete marked available remains a planned day. Any
        // available slot not occupied by a sport becomes recovery.
        let recoveryDays = Set(
            Weekday.trainingWeek.enumerated().compactMap { offset, weekday in
                guard schedule.isAvailable(on: weekday),
                      !shape.disciplines[offset].isTrainingSession else {
                    return nil
                }
                return offset
            }
        )

        var workouts: [PlannedWorkout] = []

        for (offset, discipline) in shape.disciplines.enumerated() {
            let date = day(offset)

            guard let sport = discipline.sport else {
                workouts.append(
                    recoveryDays.contains(offset)
                        ? PrescribedSessions.recoveryDay(
                            on: date,
                            goal: recoveryGoal(for: recovering)
                        )
                        : PrescribedSessions.restDay(on: date)
                )
                continue
            }

            switch sport {
            case .running:
                workouts.append(
                    PrescribedSessions.runWalk(on: date, parameters: parameters)
                )
            case .swimming:
                workouts.append(
                    PrescribedSessions.techniqueSwim(on: date, parameters: parameters)
                )
            case .cycling:
                workouts.append(
                    PrescribedSessions.easyRide(on: date, parameters: parameters)
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

    /// New onboarding stores one daily limit. The minimum also gives a safe
    /// interpretation to older profiles that still have mixed per-day limits.
    private func trainingMinuteCap(in schedule: AthleteSchedule) -> Int? {
        schedule.availableDays.compactMap(\.maxDurationMinutes).min()
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
