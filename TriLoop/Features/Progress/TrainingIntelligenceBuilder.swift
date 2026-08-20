import Foundation

/// Turns stored plans into the value types the intelligence layer works with.
///
/// The one place that knows both worlds. §3: it builds `WorkoutEvidence` and
/// routes through `WorkoutIntelligence`, so Progress reads a workout exactly as
/// the detail screen does.
@MainActor
struct TrainingIntelligenceBuilder {
    var birthDate: Date?
    var observedMaximumHeartRate: Double?
    var calendar: Calendar = .current

    var ceiling: (maximum: Double, source: HeartRateZoneSource)? {
        HeartRateCeiling.resolve(
            birthDate: birthDate,
            observedMaximum: observedMaximumHeartRate,
            asOf: .now,
            calendar: calendar
        )
    }

    /// Evidence for every completed session, with heart-rate series where the
    /// provider can supply them.
    ///
    /// §2: Progress no longer evaluates with `zones: nil`. Samples are fetched
    /// rather than stored, so the rule against duplicating HealthKit data in
    /// SwiftData still holds.
    func evidence(
        in plans: [WeeklyPlan],
        provider: (any HealthDataProviding)?
    ) async -> [WorkoutEvidence] {
        let workouts = plans
            .flatMap(\.orderedWorkouts)
            .filter { !$0.isSkipped }

        let samples = await heartRateSamples(for: workouts, provider: provider)

        return workouts
            .compactMap { workout in
                let id = workout.importedSummary?.healthKitUUID
                return evidence(from: workout, samples: id.flatMap { samples[$0] } ?? [])
            }
            .sorted { $0.date < $1.date }
    }

    func interpret(_ evidence: [WorkoutEvidence]) -> [Interpreted] {
        let resolved = ceiling
        return evidence.map { item in
            Interpreted(
                evidence: item,
                interpretation: WorkoutIntelligence.interpret(
                    item,
                    maximumHeartRate: resolved?.maximum,
                    zoneSource: resolved?.source ?? .ageBasedMaximum
                )
            )
        }
    }

    struct Interpreted {
        let evidence: WorkoutEvidence
        let interpretation: WorkoutInterpretation

        var session: LoadedSession {
            WorkoutIntelligence.session(from: evidence, interpretation: interpretation)
        }
    }

    /// Adherence outcomes, for §1's signals.
    func adherence(from interpreted: [Interpreted]) -> [SessionAdherence] {
        interpreted.compactMap { $0.interpretation.adherence?.overall }
    }

    func weeks(from plans: [WeeklyPlan], interpreted: [Interpreted]) -> [PlanWeekSessions] {
        let byDate = Dictionary(
            interpreted.map { ($0.evidence.date, $0.session) },
            uniquingKeysWith: { first, _ in first }
        )

        return plans
            .sorted { $0.startDate < $1.startDate }
            .map { plan in
                PlanWeekSessions(
                    weekNumber: plan.weekNumber,
                    startDate: plan.startDate,
                    sessions: plan.orderedWorkouts.compactMap { byDate[$0.date] }
                )
            }
    }

    /// What the plan asked for, used for §39's planned-versus-actual balance.
    func plannedSessions(in plans: [WeeklyPlan]) -> [LoadedSession] {
        plans
            .flatMap(\.orderedWorkouts)
            .compactMap { workout in
                guard let sport = workout.discipline.sport,
                      let seconds = workout.prescribedDurationSeconds ?? workout.estimatedDurationSeconds
                else { return nil }

                return LoadedSession(date: workout.date, sport: sport, durationSeconds: seconds)
            }
    }

    // MARK: - Building blocks

    /// Nil for a rest day, or a session with nothing recorded and nothing said.
    func evidence(from workout: PlannedWorkout, samples: [HeartRateReading]) -> WorkoutEvidence? {
        guard let sport = workout.discipline.sport else { return nil }

        let summary = workout.importedSummary
        guard summary != nil || workout.hasReport else { return nil }

        return WorkoutEvidence(
            date: workout.date,
            sport: sport,
            durationSeconds: summary?.duration ?? workout.prescribedDurationSeconds,
            distanceMeters: summary?.distanceMeters,
            averageHeartRate: summary?.averageHeartRate,
            heartRateSamples: samples,
            longestContinuousSwimMeters: summary?.longestContinuousSwimMeters,
            metrics: summary?.metrics ?? RecordedMetrics(),
            effort: EffortEvidence(
                targetRPE: workout.targetRPE?.upper,
                reportedRPE: workout.feedback?.rpe,
                healthKitEffort: summary?.metrics?.workoutEffort,
                estimatedHealthKitEffort: summary?.metrics?.estimatedWorkoutEffort
            ),
            plannedDurationSeconds: workout.prescribedDurationSeconds,
            targetRPE: workout.targetRPE,
            completion: completion(of: workout)
        )
    }

    func completion(of workout: PlannedWorkout) -> ExecutionComparison.Completion {
        if workout.isSkipped { return .skipped }
        if workout.importedSummary != nil || workout.hasReport { return .recorded }
        return workout.isMissed() ? .missed : .notYetDue
    }

    private func heartRateSamples(
        for workouts: [PlannedWorkout],
        provider: (any HealthDataProviding)?
    ) async -> [UUID: [HeartRateReading]] {
        guard let provider else { return [:] }
        let ids = workouts.compactMap(\.importedSummary?.healthKitUUID)
        guard !ids.isEmpty else { return [:] }

        return await withTaskGroup(of: (UUID, [HeartRateReading]).self) { group in
            for id in ids {
                group.addTask {
                    let samples = try? await provider.samples(forWorkout: id)
                    let readings = (samples?.heartRate ?? []).map {
                        HeartRateReading(date: $0.date, beatsPerMinute: $0.value)
                    }
                    return (id, readings)
                }
            }

            var result: [UUID: [HeartRateReading]] = [:]
            for await (id, readings) in group where !readings.isEmpty {
                result[id] = readings
            }
            return result
        }
    }
}
