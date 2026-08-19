#if DEBUG
import Foundation

/// Turns real Health workouts into intelligence inputs.
///
/// §16's permitted path: historical workouts feed analysis and verification,
/// never current weekly adaptation. Nothing here is persisted, attached to a
/// plan, or able to influence progression — the sessions live only as long as
/// the screen showing them.
enum RealHistoryAnalysis {

    static func sessions(
        from records: [HealthWorkoutRecord],
        asOf now: Date = .now,
        birthDate: Date?,
        calendar: Calendar = .current
    ) -> [LoadedSession] {
        // The athlete's hardest recorded effort can raise a ceiling the age
        // formula underestimates, exactly as it does for planned sessions.
        let ceiling = HeartRateCeiling.resolve(
            birthDate: birthDate,
            observedMaximum: records.compactMap(\.averageHeartRate).max(),
            asOf: now,
            calendar: calendar
        )?.maximum

        return records
            .compactMap { session(from: $0, ceiling: ceiling) }
            .sorted { $0.date < $1.date }
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

    /// Nil for activities TriLoop does not train, which have no sport to
    /// aggregate under.
    private static func session(from record: HealthWorkoutRecord, ceiling: Double?) -> LoadedSession? {
        guard let sport = record.sport else { return nil }

        let effort = EffortEvidence(
            healthKitEffort: record.metrics.workoutEffort,
            estimatedHealthKitEffort: record.metrics.estimatedWorkoutEffort
        )

        let intensity = WorkoutIntensityPolicy.intensity(
            zones: nil,
            effort: effort,
            averageHeartRate: record.averageHeartRate,
            maximumHeartRate: ceiling
        ).value?.intensity

        return LoadedSession(
            date: record.start,
            sport: sport,
            load: load(for: record, intensity: intensity),
            durationSeconds: record.duration,
            intensity: intensity,
            distanceMeters: record.distanceMeters,
            averageHeartRate: record.averageHeartRate,
            metrics: record.metrics
        )
    }

    /// Duration weighted by the classified band.
    ///
    /// Real history has almost no effort scores and no stored sample series, so
    /// the band is the only intensity evidence there is.
    private static func load(for record: HealthWorkoutRecord, intensity: WorkoutIntensity?) -> SessionLoad? {
        guard let intensity, record.duration > 0 else { return nil }

        let weight: Double = switch intensity {
        case .easy: 3
        case .moderate: 5
        case .hard: 8
        }

        return SessionLoad(
            value: (record.duration / 60) * weight,
            provenance: record.averageHeartRate != nil ? .heartRate : .healthKitEffort
        )
    }
}
#endif
