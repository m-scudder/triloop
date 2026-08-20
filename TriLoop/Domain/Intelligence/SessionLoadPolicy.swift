import Foundation

/// How much a session contributes to accumulated training (§34).
///
/// Duration multiplied by how hard it was. That is the whole model, and it is
/// deliberately simple: the athlete should be able to see why a number is what
/// it is, which §36 values more than precision the evidence cannot support.
///
/// **TriLoop Session Load is a normalized internal workload index. It is not
/// TSS, TRIMP, or a clinically validated physiological score.** Nothing should
/// present it as one.
///
/// Supported inputs, in the order they are preferred:
///
/// 1. **Time in heart-rate zones** — minutes in each zone, weighted by zone.
///    The strongest evidence, because it reflects how the session was actually
///    distributed rather than a single figure.
/// 2. **Reported effort** — duration multiplied by the athlete's RPE.
/// 3. **Apple's effort score** — the same arithmetic, used only when the
///    athlete rated nothing.
/// 4. **Intensity band** — duration multiplied by a band weight. Coarsest, used
///    only for historical workouts with an average heart rate and nothing else.
///
/// When both zone and effort evidence exist the two are averaged and the result
/// is marked `.hybrid`; neither is discarded, because they measured the same
/// session by different means.
///
/// Provenance travels with every figure, so a week built from heart rate is
/// never silently compared with one built from self-reported effort.
///
/// Known limitations:
///
/// - The weights are chosen, not measured against physiological outcomes.
/// - The four sources are not calibrated against one another beyond sharing a
///   1–10 scale, so a mixed week is approximate.
/// - Sessions with no evidence contribute nothing rather than zero, which means
///   a week's total describes only what was measured.
enum SessionLoadPolicy {

    /// Weight applied to a minute spent in each zone, on the same 1–10 scale as
    /// a reported effort.
    ///
    /// Doubling the zone number is what keeps the two sources comparable: a week
    /// mixing heart-rate sessions with self-reported ones would otherwise total
    /// nonsense. Zone 5 is capped at 10 rather than continuing upward.
    static func weight(forZone number: Int) -> Double {
        min(Double(number) * 2, 10)
    }

    /// Weight applied to a minute at each intensity band.
    ///
    /// Used only when neither time in zone nor a reported effort exists — a
    /// historical workout with an average heart rate and nothing else. Coarser
    /// than the other paths, which is why it ranks last.
    static func weight(for intensity: WorkoutIntensity) -> Double {
        switch intensity {
        case .easy: 3
        case .moderate: 5
        case .hard: 8
        }
    }

    static func load(
        durationSeconds: TimeInterval?,
        zones: HeartRateZoneBreakdown?,
        effort: EffortEvidence,
        intensity: WorkoutIntensity? = nil
    ) -> IntelligenceValue<SessionLoad> {
        let fromZones = zoneLoad(zones)
        let fromEffort = effortLoad(durationSeconds: durationSeconds, effort: effort)

        switch (fromZones, fromEffort) {
        case let (zones?, effort?):
            // Both measured the same session, so neither is discarded.
            return .available(SessionLoad(value: (zones + effort.value) / 2, provenance: .hybrid))
        case let (zones?, nil):
            return .available(SessionLoad(value: zones, provenance: .heartRate))
        case let (nil, effort?):
            return .available(effort)
        case (nil, nil):
            guard let band = bandLoad(durationSeconds: durationSeconds, intensity: intensity) else {
                // §35: no evidence is unavailable, never zero. A zero would pull
                // down every weekly average it landed in.
                return .unavailable
            }
            return .available(band)
        }
    }

    /// Duration weighted by the band, when that is all there is.
    static func bandLoad(durationSeconds: TimeInterval?, intensity: WorkoutIntensity?) -> SessionLoad? {
        guard let durationSeconds, durationSeconds > 0, let intensity else { return nil }
        return SessionLoad(
            value: (durationSeconds / 60) * weight(for: intensity),
            provenance: .heartRate
        )
    }

    /// Minutes in each zone, weighted by that zone. Uses the measured time
    /// rather than the session's total, so a gap in sampling is not invented.
    static func zoneLoad(_ zones: HeartRateZoneBreakdown?) -> Double? {
        guard let zones, zones.totalDuration > 0 else { return nil }

        return zones.zones.reduce(0) { total, zone in
            total + (zone.duration / 60) * weight(forZone: zone.number)
        }
    }

    static func effortLoad(
        durationSeconds: TimeInterval?,
        effort: EffortEvidence
    ) -> SessionLoad? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let minutes = durationSeconds / 60

        if let reported = effort.reportedRPE {
            return SessionLoad(value: minutes * Double(reported), provenance: .reportedEffort)
        }
        if let apple = effort.healthKitEffort ?? effort.estimatedHealthKitEffort {
            return SessionLoad(value: minutes * apple, provenance: .healthKitEffort)
        }
        return nil
    }
}

extension LoadProvenance {
    var explanation: String {
        switch self {
        case .heartRate: "From time in heart-rate zones."
        case .reportedEffort: "From duration and how hard it felt."
        case .healthKitEffort: "From duration and Apple's effort score."
        case .hybrid: "From heart rate and reported effort together."
        }
    }
}
