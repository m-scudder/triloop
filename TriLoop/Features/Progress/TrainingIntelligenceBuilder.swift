import Foundation

/// Turns stored plans into the value types the intelligence layer works with.
///
/// The one place that knows both worlds. Keeping it here means
/// `Domain/Intelligence` never sees a `@Model`, and the views never assemble
/// analysis inputs themselves.
@MainActor
struct TrainingIntelligenceBuilder {
    var birthDate: Date?
    var observedMaximumHeartRate: Double?
    var calendar: Calendar = .current

    /// Completed sessions across the given plans, most recent last.
    ///
    /// Only sessions that actually happened: a plan is what was intended, and
    /// mixing intention into totals would overstate every one of them.
    func completedSessions(in plans: [WeeklyPlan]) -> [LoadedSession] {
        plans
            .flatMap(\.orderedWorkouts)
            .filter { !$0.isSkipped }
            .compactMap(session(from:))
            .sorted { $0.date < $1.date }
    }

    /// What the plan asked for, used for §39's planned-versus-actual balance.
    func plannedSessions(in plans: [WeeklyPlan]) -> [LoadedSession] {
        plans
            .flatMap(\.orderedWorkouts)
            .filter { $0.discipline.sport != nil }
            .compactMap { workout in
                guard let sport = workout.discipline.sport,
                      let seconds = workout.prescribedDurationSeconds ?? workout.estimatedDurationSeconds
                else { return nil }

                return LoadedSession(date: workout.date, sport: sport, durationSeconds: seconds)
            }
    }

    func weeks(from plans: [WeeklyPlan]) -> [PlanWeekSessions] {
        plans
            .sorted { $0.startDate < $1.startDate }
            .map { plan in
                PlanWeekSessions(
                    weekNumber: plan.weekNumber,
                    startDate: plan.startDate,
                    sessions: plan.orderedWorkouts
                        .filter { !$0.isSkipped }
                        .compactMap(session(from:))
                )
            }
    }

    /// One completed session, with intensity and load derived the same way the
    /// workout detail screen derives them.
    private func session(from workout: PlannedWorkout) -> LoadedSession? {
        guard let sport = workout.discipline.sport else { return nil }

        let summary = workout.importedSummary
        let hasEvidence = summary != nil || workout.hasReport
        guard hasEvidence else { return nil }

        let effort = EffortEvidence(
            targetRPE: workout.targetRPE?.upper,
            reportedRPE: workout.feedback?.rpe,
            healthKitEffort: summary?.metrics?.workoutEffort,
            estimatedHealthKitEffort: summary?.metrics?.estimatedWorkoutEffort
        )

        // Zones need per-sample heart rate, which is not stored. The summary's
        // averages still support effort-based intensity and load, so a session
        // is never dropped for want of samples.
        let intensity = WorkoutIntensityPolicy.intensity(zones: nil, effort: effort).value?.intensity
        let duration = summary?.duration ?? workout.prescribedDurationSeconds

        return LoadedSession(
            date: workout.date,
            sport: sport,
            load: SessionLoadPolicy.load(durationSeconds: duration, zones: nil, effort: effort).value,
            durationSeconds: duration,
            intensity: intensity,
            distanceMeters: summary?.distanceMeters,
            averageHeartRate: summary?.averageHeartRate,
            longestContinuousSwimMeters: summary?.longestContinuousSwimMeters,
            metrics: summary?.metrics ?? RecordedMetrics()
        )
    }
}
