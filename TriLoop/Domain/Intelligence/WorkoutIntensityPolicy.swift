import Foundation

/// Decides how hard a session was, from whatever evidence exists (§33).
///
/// Deterministic and missing-data aware. The rule that matters most: no
/// evidence produces `.unavailable`, never `.easy`. A session with no heart
/// rate and no report is unknown, and calling it easy would quietly understate
/// every total built on top of it.
enum WorkoutIntensityPolicy {

    /// Time in the top two zones beyond which a session reads as hard.
    ///
    /// A fifth of a session spent above 80% of maximum is a hard session by any
    /// reasonable reading, even if the rest was gentle.
    static let hardZoneShare = 0.20
    /// Combined time at or above zone 3 beyond which it is at least moderate.
    static let moderateZoneShare = 0.25

    static func intensity(
        zones: HeartRateZoneBreakdown?,
        effort: EffortEvidence
    ) -> IntelligenceValue<WorkoutIntensityReading> {
        var candidates: [(intensity: WorkoutIntensity, evidence: IntensityEvidence)] = []

        if let zones, let fromZones = intensity(from: zones) {
            candidates.append((fromZones, .heartRateZones))
        }

        // The athlete's own rating outranks Apple's estimate; they are not
        // averaged, because §26 keeps the two claims distinct.
        if let reported = effort.reportedRPE {
            candidates.append((intensity(fromRPE: reported), .reportedEffort))
        } else if let apple = effort.healthKitEffort ?? effort.estimatedHealthKitEffort {
            candidates.append((intensity(fromRPE: Int(apple.rounded())), .healthKitEffort))
        }

        guard let first = candidates.first else { return .unavailable }
        guard candidates.count > 1 else {
            return .available(WorkoutIntensityReading(intensity: first.intensity, evidence: first.evidence))
        }

        let distinct = Set(candidates.map(\.intensity))
        if distinct.count == 1 {
            return .available(WorkoutIntensityReading(intensity: first.intensity, evidence: .hybrid))
        }

        // Sources disagree — an easy heart rate against a high reported effort,
        // say. Take the harder reading rather than splitting the difference, and
        // record that it was contested so §51 can surface the uncertainty.
        let hardest = candidates.map(\.intensity).max { rank($0) < rank($1) } ?? first.intensity
        return .available(WorkoutIntensityReading(intensity: hardest, evidence: .conflicting))
    }

    /// Nil when the breakdown measured nothing, so an empty session does not
    /// register as easy.
    static func intensity(from zones: HeartRateZoneBreakdown) -> WorkoutIntensity? {
        guard zones.totalDuration > 0 else { return nil }

        let byNumber = Dictionary(uniqueKeysWithValues: zones.zones.map { ($0.number, zones.share(of: $0)) })
        let hard = (byNumber[4] ?? 0) + (byNumber[5] ?? 0)
        let moderate = byNumber[3] ?? 0

        if hard >= hardZoneShare { return .hard }
        if hard + moderate >= moderateZoneShare { return .moderate }
        return .easy
    }

    /// Shared by TriLoop RPE and Apple's effort score, which use the same 1–10
    /// scale even though they ask different questions.
    static func intensity(fromRPE rpe: Int) -> WorkoutIntensity {
        switch rpe {
        case ...4: .easy
        case 5...6: .moderate
        default: .hard
        }
    }

    private static func rank(_ intensity: WorkoutIntensity) -> Int {
        switch intensity {
        case .easy: 0
        case .moderate: 1
        case .hard: 2
        }
    }
}

extension WorkoutIntensity {
    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .hard: "Hard"
        }
    }
}

extension IntensityEvidence {
    /// Says what the reading rests on, so a contested one is never presented as
    /// settled.
    var explanation: String {
        switch self {
        case .heartRateZones: "From time in heart-rate zones."
        case .reportedEffort: "From how hard you said it felt."
        case .healthKitEffort: "From Apple's effort score."
        case .hybrid: "Heart rate and reported effort agree."
        case .conflicting: "Heart rate and reported effort disagree; the harder reading is shown."
        }
    }
}
