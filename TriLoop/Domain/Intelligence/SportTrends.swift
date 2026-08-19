import Foundation

/// Two comparable sessions, far enough apart to say something.
///
/// §44's "similar easy runs" comparison: the same kind of session, then and
/// now, which is far more meaningful than comparing a hard session with an easy
/// one and calling the difference progress.
struct SimilarSessionComparison: Equatable, Sendable {
    let earlier: LoadedSession
    let latest: LoadedSession

    var paceChange: Double? {
        guard let earlierPace = earlier.pacePerKilometre,
              let latestPace = latest.pacePerKilometre else { return nil }
        return latestPace - earlierPace
    }

    var heartRateChange: Double? {
        guard let earlierHR = earlier.averageHeartRate,
              let latestHR = latest.averageHeartRate else { return nil }
        return latestHR - earlierHR
    }

    /// The one claim the evidence supports: faster at a similar heart rate.
    ///
    /// Deliberately narrow. §44 rules out "fitness increased 12%", and this
    /// wording states only what was observed.
    var summary: String? {
        guard let paceChange, let heartRateChange else { return nil }

        let faster = paceChange < -5
        let slower = paceChange > 5
        let similarEffort = abs(heartRateChange) <= 3

        return switch (faster, slower, similarEffort) {
        case (true, _, true): "Recent easy runs are trending faster at a similar heart rate."
        case (true, _, false) where heartRateChange < 0: "Recent easy runs are faster at a lower heart rate."
        case (true, _, false): "Recent easy runs are faster, at a higher heart rate."
        case (_, true, true): "Recent easy runs are slower at a similar heart rate."
        default: nil
        }
    }
}

/// Running trends (§44).
enum RunningTrends {

    /// How close two sessions must be in duration to count as comparable.
    static let durationTolerance = 0.30

    static func weeklyDistance(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor, combine: TrendAnalysis.totalDistance)
    }

    static func weeklyDuration(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor, combine: TrendAnalysis.totalDuration)
    }

    static func pace(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor, combine: TrendAnalysis.averagePace)
    }

    static func heartRate(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor, combine: TrendAnalysis.averageHeartRate)
    }

    /// Average running power, where the hardware recorded it.
    static func power(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor) {
            TrendAnalysis.mean($0.compactMap(\.metrics.averageRunningPower))
        }
    }

    /// The earliest and latest comparable easy runs.
    ///
    /// Matched on intensity and duration so the comparison is like for like;
    /// otherwise a short sprint and a long jog would appear to show a collapse
    /// in pace.
    static func similarEasyRuns(_ sessions: [LoadedSession]) -> SimilarSessionComparison? {
        let candidates = sessions
            .filter { $0.sport == .running && $0.intensity == .easy }
            .filter { $0.pacePerKilometre != nil && $0.averageHeartRate != nil }
            .sorted { $0.date < $1.date }

        guard let latest = candidates.last else { return nil }

        let comparable = candidates.dropLast().filter { candidate in
            guard let a = candidate.durationSeconds, let b = latest.durationSeconds, b > 0 else { return false }
            return abs(a - b) / b <= durationTolerance
        }

        guard let earlier = comparable.first else { return nil }
        return SimilarSessionComparison(earlier: earlier, latest: latest)
    }

    private static func trend(
        _ sessions: [LoadedSession],
        anchor: Date,
        combine: @escaping ([LoadedSession]) -> Double?
    ) -> IntelligenceValue<MetricTrend> {
        let running = sessions.filter { $0.sport == .running }
        guard !running.isEmpty else { return .unavailable }

        return TrendAnalysis.trend(
            from: TrendAnalysis.weeklyValues(running, anchoredTo: anchor, combine: combine)
        )
    }
}

/// Swimming trends (§45).
enum SwimmingTrends {

    static func weeklyVolume(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor, combine: TrendAnalysis.totalDistance)
    }

    /// Elapsed pace, rests included.
    ///
    /// Named for what it is. §45 forbids mixing this with active pace, and the
    /// two are only distinguishable if neither is called simply "pace".
    static func elapsedPace(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor) { weekSessions in
            let paces = weekSessions.compactMap(\.elapsedSwimPacePer100m)
            return TrendAnalysis.mean(paces)
        }
    }

    /// Longest unbroken swim per week, which is what beginner progress is
    /// actually made of.
    static func longestContinuous(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor) {
            $0.compactMap(\.longestContinuousSwimMeters).max()
        }
    }

    private static func trend(
        _ sessions: [LoadedSession],
        anchor: Date,
        combine: @escaping ([LoadedSession]) -> Double?
    ) -> IntelligenceValue<MetricTrend> {
        let swims = sessions.filter { $0.sport == .swimming }
        guard !swims.isEmpty else { return .unavailable }

        return TrendAnalysis.trend(
            from: TrendAnalysis.weeklyValues(swims, anchoredTo: anchor, combine: combine)
        )
    }
}

/// Cycling trends (§46).
///
/// Power and cadence are optional throughout: most riders have neither, and
/// §46 requires those sections to disappear rather than show zeros.
enum CyclingTrends {

    static func weeklyDuration(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor, combine: TrendAnalysis.totalDuration)
    }

    static func weeklyDistance(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor, combine: TrendAnalysis.totalDistance)
    }

    /// Metres per second, averaged over the week's riding.
    static func speed(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor) { weekSessions in
            let distance = weekSessions.compactMap(\.distanceMeters).reduce(0, +)
            let seconds = weekSessions.compactMap(\.durationSeconds).reduce(0, +)
            guard distance > 0, seconds > 0 else { return nil }
            return distance / seconds
        }
    }

    static func heartRate(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor, combine: TrendAnalysis.averageHeartRate)
    }

    static func cadence(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor) {
            TrendAnalysis.mean($0.compactMap(\.metrics.averageCyclingCadence))
        }
    }

    static func power(_ sessions: [LoadedSession], anchoredTo anchor: Date) -> IntelligenceValue<MetricTrend> {
        trend(sessions, anchor: anchor) {
            TrendAnalysis.mean($0.compactMap(\.metrics.averageCyclingPower))
        }
    }

    private static func trend(
        _ sessions: [LoadedSession],
        anchor: Date,
        combine: @escaping ([LoadedSession]) -> Double?
    ) -> IntelligenceValue<MetricTrend> {
        let rides = sessions.filter { $0.sport == .cycling }
        guard !rides.isEmpty else { return .unavailable }

        return TrendAnalysis.trend(
            from: TrendAnalysis.weeklyValues(rides, anchoredTo: anchor, combine: combine)
        )
    }
}
