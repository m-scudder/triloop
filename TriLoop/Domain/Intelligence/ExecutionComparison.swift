import Foundation

/// Compares what was prescribed with what actually happened (§30).
///
/// Pure and deterministic. Reports named states rather than an adherence
/// percentage, because "84% adherent" cannot distinguish going too hard from
/// stopping early, and those call for opposite coaching responses.
enum ExecutionComparison {

    /// How far from the prescription still counts as following it (§31).
    ///
    /// A fraction alone punishes short sessions unfairly — 10% of a 20-minute
    /// swim is two minutes, which is well inside the noise of getting changed
    /// and starting a watch — so a floor applies as well.
    struct Tolerance: Equatable, Sendable {
        var fraction: Double = 0.10
        var minimumSeconds: TimeInterval = 120
        /// Below this share of the prescription the session did not really
        /// happen, however willing the athlete was.
        var incompleteBelow: Double = 0.5

        static let standard = Tolerance()

        func allowance(for plannedSeconds: TimeInterval) -> TimeInterval {
            max(plannedSeconds * fraction, minimumSeconds)
        }
    }

    /// What the record says about whether the session took place.
    enum Completion: Equatable, Sendable {
        case recorded
        case skipped
        case missed
        /// Still in the future, so there is nothing to compare yet.
        case notYetDue
    }

    /// Duration, effort, and the single answer §32 shows as the result.
    struct Outcome: Equatable, Sendable {
        var duration: SessionAdherence?
        var effort: SessionAdherence?
        var overall: SessionAdherence
    }

    static func compare(
        plannedSeconds: TimeInterval?,
        actualSeconds: TimeInterval?,
        targetRPE: RPERange?,
        reportedRPE: Int?,
        completion: Completion,
        tolerance: Tolerance = .standard
    ) -> Outcome? {
        switch completion {
        case .notYetDue:
            return nil
        case .skipped:
            return Outcome(overall: .skipped)
        case .missed:
            return Outcome(overall: .missed)
        case .recorded:
            break
        }

        let duration = durationAdherence(
            planned: plannedSeconds,
            actual: actualSeconds,
            tolerance: tolerance
        )
        let effort = effortAdherence(target: targetRPE, reported: reportedRPE)

        // A session with neither a duration nor an effort to compare is still a
        // completed session; there is simply nothing to say about execution.
        let overall = [duration, effort]
            .compactMap { $0 }
            .max(by: { severity($0) < severity($1) }) ?? .withinTarget

        return Outcome(duration: duration, effort: effort, overall: overall)
    }

    static func durationAdherence(
        planned: TimeInterval?,
        actual: TimeInterval?,
        tolerance: Tolerance = .standard
    ) -> SessionAdherence? {
        guard let planned, planned > 0, let actual else { return nil }

        if actual < planned * tolerance.incompleteBelow { return .incomplete }

        let allowance = tolerance.allowance(for: planned)
        if actual < planned - allowance { return .belowTarget }
        if actual > planned + allowance { return .aboveTarget }
        return .withinTarget
    }

    static func effortAdherence(target: RPERange?, reported: Int?) -> SessionAdherence? {
        guard let target, let reported else { return nil }

        if reported < target.lower { return .belowTarget }
        if reported > target.upper { return .aboveTarget }
        return .withinTarget
    }

    /// Ordering used to pick the headline result.
    ///
    /// Training harder than prescribed outranks training easier: one is a
    /// safety signal, the other is usually just life getting in the way.
    private static func severity(_ adherence: SessionAdherence) -> Int {
        switch adherence {
        case .withinTarget: 0
        case .belowTarget: 1
        case .aboveTarget: 2
        case .incomplete: 3
        case .missed: 4
        case .skipped: 5
        }
    }
}

extension SessionAdherence {
    var displayName: String {
        switch self {
        case .withinTarget: "Within target"
        case .aboveTarget: "Above target"
        case .belowTarget: "Below target"
        case .incomplete: "Incomplete"
        case .skipped: "Skipped"
        case .missed: "Missed"
        }
    }
}
