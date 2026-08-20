#if DEBUG
import Foundation

/// Turns real Health workouts into intelligence inputs.
///
/// §12: routes through the shared `WorkoutIntelligence` rather than repeating
/// the calculations, so a historical workout is read exactly as an imported one
/// would be. §16 keeps it read-only and away from current training.
enum RealHistoryAnalysis {

    /// Fetches heart-rate series so time in zone can be used where it exists.
    ///
    /// §4 prefers a series over an average; the average survives only as a
    /// fallback for workouts that never recorded one.
    static func sessions(
        from records: [HealthWorkoutRecord],
        provider: any HealthDataProviding,
        birthDate: Date?,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) async -> [LoadedSession] {
        let trained = records.filter { $0.sport != nil }
        guard !trained.isEmpty else { return [] }

        let ceiling = HeartRateCeiling.resolve(
            birthDate: birthDate,
            observedMaximum: trained.compactMap(\.averageHeartRate).max(),
            asOf: now,
            calendar: calendar
        )

        let samples = await heartRateSamples(for: trained, provider: provider)

        return trained
            .compactMap { record -> LoadedSession? in
                guard let evidence = evidence(from: record, samples: samples[record.id] ?? []) else {
                    return nil
                }
                let interpretation = WorkoutIntelligence.interpret(
                    evidence,
                    maximumHeartRate: ceiling?.maximum,
                    zoneSource: ceiling?.source ?? .ageBasedMaximum
                )
                return WorkoutIntelligence.session(from: evidence, interpretation: interpretation)
            }
            .sorted { $0.date < $1.date }
    }

    /// Concurrent because a year of history is a lot of separate lookups.
    private static func heartRateSamples(
        for records: [HealthWorkoutRecord],
        provider: any HealthDataProviding
    ) async -> [UUID: [HeartRateReading]] {
        await withTaskGroup(of: (UUID, [HeartRateReading]).self) { group in
            for record in records {
                group.addTask {
                    let samples = try? await provider.samples(forWorkout: record.id)
                    let readings = (samples?.heartRate ?? []).map {
                        HeartRateReading(date: $0.date, beatsPerMinute: $0.value)
                    }
                    return (record.id, readings)
                }
            }

            var result: [UUID: [HeartRateReading]] = [:]
            for await (id, readings) in group where !readings.isEmpty {
                result[id] = readings
            }
            return result
        }
    }

    /// Nil for activities TriLoop does not train, which have no sport to
    /// aggregate under.
    static func evidence(
        from record: HealthWorkoutRecord,
        samples: [HeartRateReading]
    ) -> WorkoutEvidence? {
        guard let sport = record.sport else { return nil }

        return WorkoutEvidence(
            date: record.start,
            sport: sport,
            durationSeconds: record.duration,
            distanceMeters: record.distanceMeters,
            averageHeartRate: record.averageHeartRate,
            heartRateSamples: samples,
            metrics: record.metrics,
            effort: EffortEvidence(
                healthKitEffort: record.metrics.workoutEffort,
                estimatedHealthKitEffort: record.metrics.estimatedWorkoutEffort
            ),
            // No plan asked for these, so there is nothing to compare against.
            completion: .recorded
        )
    }

    /// Seven-day buckets counted back from today.
    ///
    /// Real history predates every plan, so §37's plan-week aggregation has
    /// nothing to anchor to and rolling weeks are the honest substitute.
    static func rollingWeeks(
        of sessions: [LoadedSession],
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeeklyLoad] {
        let today = calendar.startOfDay(for: now)

        let grouped = Dictionary(grouping: sessions) { session -> Date in
            let days = calendar.dateComponents([.day], from: session.date, to: today).day ?? 0
            return calendar.date(byAdding: .day, value: -(days / 7) * 7, to: today) ?? today
        }

        return grouped
            .sorted { $0.key < $1.key }
            .enumerated()
            .compactMap { index, entry in
                WeeklyTrainingLoad.load(
                    for: PlanWeekSessions(
                        weekNumber: index + 1,
                        startDate: entry.key,
                        sessions: entry.value
                    )
                ).value
            }
    }
}
#endif
