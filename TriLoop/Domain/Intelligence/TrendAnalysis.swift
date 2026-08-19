import Foundation

/// One week's value for a tracked metric.
struct TrendPoint: Equatable, Sendable {
    let weekStart: Date
    let value: Double
    /// Sessions the value was averaged or totalled over.
    let sampleCount: Int
}

/// Which way a metric has moved, without saying whether that is good.
///
/// §44 forbids unsupported fitness claims. "Falling" is an observation;
/// "fitness increased 12%" is a conclusion the data cannot carry.
enum TrendDirection: String, Sendable {
    case rising
    case steady
    case falling
}

/// A metric tracked across weeks.
struct MetricTrend: Equatable, Sendable {
    let points: [TrendPoint]
    let direction: TrendDirection

    var earliest: TrendPoint? { points.first }
    var latest: TrendPoint? { points.last }

    /// Change from the first tracked week to the last, in the metric's units.
    var change: Double? {
        guard let earliest, let latest, points.count > 1 else { return nil }
        return latest.value - earliest.value
    }
}

/// Builds week-by-week trends from completed sessions.
enum TrendAnalysis {

    /// Weeks needed before a direction is claimed at all.
    ///
    /// Two points make a line, which is not a trend: one good week would read
    /// as improvement. Three is the least that can show a direction.
    static let minimumWeeks = 3

    /// Movement smaller than this share of the starting value is called steady,
    /// so ordinary week-to-week noise is not dressed up as progress.
    static let steadyTolerance = 0.03

    /// Groups sessions into weeks anchored to a start date.
    ///
    /// Anchored to the plan rather than to `Calendar`'s first weekday, for the
    /// same reason §37 aggregates by plan week.
    static func weeklyValues(
        _ sessions: [LoadedSession],
        anchoredTo anchor: Date,
        calendar: Calendar = .current,
        combine: ([LoadedSession]) -> Double?
    ) -> [TrendPoint] {
        let startOfAnchor = calendar.startOfDay(for: anchor)

        let grouped = Dictionary(grouping: sessions) { session -> Date in
            let days = calendar.dateComponents([.day], from: startOfAnchor, to: session.date).day ?? 0
            // Integer division floors toward zero, which would put the week
            // before the anchor in the same bucket as the week after it.
            let weekIndex = Int(floor(Double(days) / 7))
            return calendar.date(byAdding: .day, value: weekIndex * 7, to: startOfAnchor) ?? startOfAnchor
        }

        return grouped
            .compactMap { weekStart, weekSessions -> TrendPoint? in
                guard let value = combine(weekSessions) else { return nil }
                return TrendPoint(weekStart: weekStart, value: value, sampleCount: weekSessions.count)
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    static func trend(from points: [TrendPoint]) -> IntelligenceValue<MetricTrend> {
        guard points.count >= minimumWeeks else {
            return .insufficientHistory(found: points.count, required: minimumWeeks)
        }

        let ordered = points.sorted { $0.weekStart < $1.weekStart }
        return .available(
            MetricTrend(points: ordered, direction: direction(of: ordered))
        )
    }

    /// Compares the first and last halves rather than just the endpoints, so a
    /// single unusual week does not decide the direction.
    static func direction(of points: [TrendPoint]) -> TrendDirection {
        guard points.count >= 2 else { return .steady }

        let half = points.count / 2
        let first = points.prefix(half)
        let last = points.suffix(half)

        let firstMean = first.reduce(0) { $0 + $1.value } / Double(first.count)
        let lastMean = last.reduce(0) { $0 + $1.value } / Double(last.count)

        guard firstMean != 0 else { return lastMean > 0 ? .rising : .steady }

        let change = (lastMean - firstMean) / abs(firstMean)
        if change > steadyTolerance { return .rising }
        if change < -steadyTolerance { return .falling }
        return .steady
    }

    // MARK: - Common combiners

    static func totalDuration(_ sessions: [LoadedSession]) -> Double? {
        let total = sessions.compactMap(\.durationSeconds).reduce(0, +)
        return total > 0 ? total : nil
    }

    static func totalDistance(_ sessions: [LoadedSession]) -> Double? {
        let total = sessions.compactMap(\.distanceMeters).reduce(0, +)
        return total > 0 ? total : nil
    }

    static func averageHeartRate(_ sessions: [LoadedSession]) -> Double? {
        mean(sessions.compactMap(\.averageHeartRate))
    }

    /// Distance-weighted, because averaging the paces of a 2 km and a 10 km run
    /// would let the short one count as much as the long one.
    static func averagePace(_ sessions: [LoadedSession]) -> Double? {
        let usable = sessions.filter { $0.pacePerKilometre != nil && ($0.distanceMeters ?? 0) > 0 }
        guard !usable.isEmpty else { return nil }

        let distance = usable.compactMap(\.distanceMeters).reduce(0, +)
        let seconds = usable.compactMap(\.durationSeconds).reduce(0, +)
        guard distance > 0, seconds > 0 else { return nil }
        return seconds / (distance / 1_000)
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
