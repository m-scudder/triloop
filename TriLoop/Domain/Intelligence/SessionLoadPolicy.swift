import Foundation

/// How much a session contributes to accumulated training (§34).
///
/// Duration multiplied by how hard it was. That is the whole model, and it is
/// deliberately simple: the athlete should be able to see why a number is what
/// it is, which §36 values more than precision the evidence cannot support.
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

    static func load(
        durationSeconds: TimeInterval?,
        zones: HeartRateZoneBreakdown?,
        effort: EffortEvidence
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
            // §35: no evidence is unavailable, never zero. A zero would pull
            // down every weekly average it landed in.
            return .unavailable
        }
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
