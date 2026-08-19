import Foundation

/// Turns heart-rate readings into time spent in each zone.
///
/// Pure and deterministic: the same readings and the same ceiling always give
/// the same breakdown, so a zone chart can be reasoned about without a device.
struct HeartRateZoneCalculator {

    /// Upper bound of each zone as a fraction of maximum heart rate.
    ///
    /// Percentage-of-max rather than heart-rate reserve: reserve needs a
    /// resting rate as well, which doubles the ways the calculation can be
    /// unavailable for no gain in explainability.
    static let upperBounds: [Double] = [0.60, 0.70, 0.80, 0.90]

    let maximumHeartRate: Double
    let source: HeartRateZoneSource

    /// Zone 1 starts at zero rather than 50% of max, so every recorded beat is
    /// accounted for and the durations sum to the time actually measured.
    func boundaries() -> [(lower: Double, upper: Double?)] {
        var result: [(Double, Double?)] = []
        var lower: Double = 0

        for fraction in Self.upperBounds {
            let upper = (maximumHeartRate * fraction).rounded()
            result.append((lower, upper))
            lower = upper
        }
        result.append((lower, nil))
        return result
    }

    func zone(for beatsPerMinute: Double) -> Int {
        let bounds = boundaries()
        for (index, bound) in bounds.enumerated() {
            if let upper = bound.upper, beatsPerMinute < upper { return index + 1 }
        }
        return bounds.count
    }

    /// Time in each zone, measured from the gaps between readings.
    ///
    /// Returns nil when there is nothing to describe: §55 forbids reporting a
    /// session of all-zero zones as though it were measured.
    func breakdown(from readings: [HeartRateReading]) -> HeartRateZoneBreakdown? {
        guard maximumHeartRate > 0, readings.count > 1 else { return nil }

        let ordered = readings.sorted { $0.date < $1.date }
        var durations = [TimeInterval](repeating: 0, count: Self.upperBounds.count + 1)

        for (index, reading) in ordered.enumerated() {
            // The last reading has no successor; give it the median gap rather
            // than dropping it or assuming a fixed minute.
            let seconds = index < ordered.count - 1
                ? ordered[index + 1].date.timeIntervalSince(reading.date)
                : medianGap(of: ordered)

            guard seconds > 0 else { continue }
            durations[zone(for: reading.beatsPerMinute) - 1] += seconds
        }

        let bounds = boundaries()
        let zones = durations.enumerated().map { index, duration in
            HeartRateZone(
                number: index + 1,
                lowerBoundBPM: bounds[index].lower,
                upperBoundBPM: bounds[index].upper,
                duration: duration
            )
        }

        guard zones.contains(where: { $0.duration > 0 }) else { return nil }
        return HeartRateZoneBreakdown(zones: zones, source: source)
    }

    /// Resistant to a single long pause, which a mean would smear across the
    /// whole session.
    private func medianGap(of readings: [HeartRateReading]) -> TimeInterval {
        let gaps = zip(readings, readings.dropFirst())
            .map { $1.date.timeIntervalSince($0.date) }
            .filter { $0 > 0 }
            .sorted()

        guard !gaps.isEmpty else { return 0 }
        return gaps[gaps.count / 2]
    }
}

/// Decides what a session's zones can be anchored to.
///
/// §55: when neither an age nor a hard effort is known, zones are unavailable
/// rather than estimated from a guess.
enum HeartRateCeiling {

    /// The conventional age-predicted maximum. Carries roughly ±10–12 bpm of
    /// individual error, which is why the athlete's own observed effort wins
    /// when it is higher.
    static func ageBased(birthDate: Date, asOf now: Date, calendar: Calendar = .current) -> Double? {
        let years = calendar.dateComponents([.year], from: birthDate, to: now).year
        guard let years, years >= 10, years <= 100 else { return nil }
        return Double(220 - years)
    }

    /// Resolves the ceiling, preferring whichever evidence is stronger.
    ///
    /// A recorded effort above the age prediction is not an error — the formula
    /// is a population average, and the athlete actually did it.
    static func resolve(
        birthDate: Date?,
        observedMaximum: Double?,
        asOf now: Date,
        calendar: Calendar = .current
    ) -> (maximum: Double, source: HeartRateZoneSource)? {
        let predicted = birthDate.flatMap { ageBased(birthDate: $0, asOf: now, calendar: calendar) }

        switch (predicted, observedMaximum) {
        case let (predicted?, observed?):
            return observed > predicted ? (observed, .observedMaximum) : (predicted, .ageBasedMaximum)
        case let (predicted?, nil):
            return (predicted, .ageBasedMaximum)
        case let (nil, observed?):
            return (observed, .observedMaximum)
        case (nil, nil):
            return nil
        }
    }
}
