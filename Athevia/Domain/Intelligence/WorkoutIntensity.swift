import Foundation

/// How hard a session was.
///
/// §33: three bands, not a number. The evidence behind them — a few heart-rate
/// samples, a self-reported rating — does not support finer resolution, and
/// §36 forbids inventing precision the data cannot carry.
enum WorkoutIntensity: String, CaseIterable, Sendable {
    case easy
    case moderate
    case hard
}

/// What the intensity reading was based on.
///
/// §35 applies the same rule to intensity as to load: the athlete should be
/// able to see why a session was called hard.
enum IntensityEvidence: String, Sendable {
    case heartRateZones
    case reportedEffort
    case healthKitEffort
    /// Several sources agreed.
    case hybrid
    /// Several sources disagreed, and the reading reflects the more cautious one.
    case conflicting
}

/// An intensity reading together with what produced it.
struct WorkoutIntensityReading: Equatable, Sendable {
    let intensity: WorkoutIntensity
    let evidence: IntensityEvidence
}

/// A session's contribution to accumulated training.
///
/// §34: deliberately not called TSS or TRIMP. Those are defined standards, and
/// borrowing the name for a different calculation would misrepresent it.
struct SessionLoad: Equatable, Sendable {
    let value: Double
    let provenance: LoadProvenance
}

/// What a load figure was computed from.
///
/// §35: kept alongside every load so a week built from heart rate is never
/// silently compared with one built from self-reported effort.
enum LoadProvenance: String, Sendable {
    case heartRate
    case reportedEffort
    case healthKitEffort
    case hybrid
}
