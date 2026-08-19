import Foundation

/// One reading of a recovery metric.
struct RecoveryReading: Equatable, Sendable {
    let date: Date
    let value: Double

    init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// An athlete-relative baseline and how the latest reading sits against it.
struct PhysiologicalBaseline: Equatable, Sendable {
    let window: BaselineWindow
    let average: Double
    let readingCount: Int
    /// Most recent reading, which is what the athlete is compared against.
    let latest: Double?

    /// Difference from the baseline, in the metric's own units.
    var deviation: Double? {
        latest.map { $0 - average }
    }

    /// Whether the latest reading sits meaningfully outside the recent range.
    ///
    /// Nil when there is nothing recent to judge.
    func standing(tolerance: Double) -> BaselineStanding? {
        guard let deviation else { return nil }
        if deviation > tolerance { return .above }
        if deviation < -tolerance { return .below }
        return .withinRange
    }
}

/// Where a reading sits relative to the athlete's own recent history.
///
/// §43: an observation, never a diagnosis. "Above your recent range" is a fact;
/// "you are overtrained" is a clinical claim TriLoop is not entitled to make.
enum BaselineStanding: String, Sendable {
    case below
    case withinRange
    case above
}

/// Builds athlete-relative baselines (§41).
enum PhysiologicalBaselinePolicy {

    /// How far from the baseline still counts as normal, as a fraction of the
    /// baseline itself.
    ///
    /// Proportional rather than absolute because the metrics have wildly
    /// different scales: 5 ms of HRV is noise, 5 bpm of resting heart rate is not.
    static let tolerance = 0.07

    static func baseline(
        from readings: [RecoveryReading],
        window: BaselineWindow,
        asOf now: Date,
        calendar: Calendar = .current
    ) -> IntelligenceValue<PhysiologicalBaseline> {
        guard let earliest = calendar.date(byAdding: .day, value: -window.days, to: now) else {
            return .unavailable
        }

        let recent = readings
            .filter { $0.date > earliest && $0.date <= now }
            .sorted { $0.date < $1.date }

        return MinimumHistoryPolicy.value(
            readingCount: recent.count,
            window: window
        ) {
            PhysiologicalBaseline(
                window: window,
                average: recent.reduce(0) { $0 + $1.value } / Double(recent.count),
                readingCount: recent.count,
                latest: recent.last?.value
            )
        }
    }

    /// Reads a standing in plain language, respecting which direction is good.
    ///
    /// §43's wording rules: describe the observation, leave the conclusion to
    /// the athlete.
    static func describe(
        _ standing: BaselineStanding,
        metric name: String,
        higherIsBetter: Bool
    ) -> String {
        switch standing {
        case .withinRange:
            "\(name) is within your recent range."
        case .above:
            higherIsBetter
                ? "\(name) is above your recent range."
                : "\(name) is above your recent baseline."
        case .below:
            higherIsBetter
                ? "\(name) is below your recent range."
                : "\(name) is below your recent baseline."
        }
    }
}
