import Foundation

/// How a session's execution compared with its prescription.
///
/// §31: deliberately named states rather than an adherence percentage. "84%
/// adherent" hides whether the athlete went too hard, stopped early, or never
/// started — and those need different coaching responses.
enum SessionAdherence: String, CaseIterable, Sendable {
    case withinTarget
    case aboveTarget
    case belowTarget
    /// Started and recorded, but short of what was prescribed.
    case incomplete
    /// The athlete deliberately stood the session down.
    case skipped
    /// The day passed with nothing recorded and nothing said.
    case missed
}

/// The effort evidence available for one session.
///
/// §26 keeps these four separate on purpose: the athlete's own rating and
/// Apple's estimate are different claims, and averaging them would destroy the
/// disagreement that §33 needs in order to report conflicting evidence.
struct EffortEvidence: Equatable, Sendable {
    /// What the plan asked for, 1–10.
    var targetRPE: Int?
    /// What the athlete reported, 1–10.
    var reportedRPE: Int?
    /// `HKWorkoutEffortScore`, as recorded by the athlete in Apple's ecosystem.
    var healthKitEffort: Double?
    /// `HKWorkoutEstimatedEffortScore`, as inferred by the system.
    var estimatedHealthKitEffort: Double?

    var hasAnyEvidence: Bool {
        reportedRPE != nil || healthKitEffort != nil || estimatedHealthKitEffort != nil
    }
}
