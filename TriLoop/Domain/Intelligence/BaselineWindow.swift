import Foundation

/// The windows athlete-relative baselines are built over.
///
/// §41: a reading only means something against the athlete's own recent range,
/// so both a short and a long window are kept — the short one moves with the
/// current week, the long one is what "normal" is measured against.
enum BaselineWindow: CaseIterable, Sendable {
    case sevenDay
    case twentyEightDay

    var days: Int {
        switch self {
        case .sevenDay: 7
        case .twentyEightDay: 28
        }
    }

    /// Readings needed before a baseline is reported at all.
    ///
    /// Below full coverage on purpose: Health data is genuinely intermittent —
    /// a watch comes off, sleep goes unrecorded — and demanding one reading per
    /// day would mean almost never showing a baseline. Set high enough that a
    /// couple of stray readings cannot masquerade as a trend.
    var minimumReadings: Int {
        switch self {
        case .sevenDay: 4
        case .twentyEightDay: 14
        }
    }
}

/// The single place that decides whether there is enough history.
///
/// §42: the threshold lives in the domain, so a view cannot invent its own and
/// two screens cannot disagree about whether a baseline exists.
enum MinimumHistoryPolicy {

    static func hasEnough(readingCount: Int, for window: BaselineWindow) -> Bool {
        readingCount >= window.minimumReadings
    }

    /// Computes a baseline only when the history supports it, and otherwise
    /// reports exactly what is missing.
    static func value<Value>(
        readingCount: Int,
        window: BaselineWindow,
        compute: () -> Value
    ) -> IntelligenceValue<Value> {
        guard hasEnough(readingCount: readingCount, for: window) else {
            return .insufficientHistory(found: readingCount, required: window.minimumReadings)
        }
        return .available(compute())
    }
}
