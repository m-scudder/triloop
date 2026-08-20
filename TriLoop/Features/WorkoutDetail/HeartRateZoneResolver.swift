import Foundation

/// Builds a zone breakdown for one session from whatever the app knows.
///
/// Sits at the feature layer because it bridges data-layer samples to the
/// Foundation-only intelligence layer; the calculation itself stays in
/// `HeartRateZoneCalculator` and is tested without any of this.
enum HeartRateZoneResolver {

    /// Why a breakdown could not be produced.
    ///
    /// §55: each reason needs a different response from the athlete, so they
    /// are not collapsed into a single "unavailable".
    enum Unavailable: Error, Equatable {
        case noHeartRateSamples
        case noCeiling
    }

    static func breakdown(
        heartRate: [SamplePoint],
        birthDate: Date?,
        observedMaximum: Double?,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> Result<HeartRateZoneBreakdown, Unavailable> {
        guard heartRate.count > 1 else { return .failure(.noHeartRateSamples) }

        guard let ceiling = HeartRateCeiling.resolve(
            birthDate: birthDate,
            observedMaximum: observedMaximum,
            asOf: now,
            calendar: calendar
        ) else {
            return .failure(.noCeiling)
        }

        // Delegates rather than calculating: §3 allows only one zone
        // implementation, and this type exists for the reason, not the maths.
        let evidence = WorkoutEvidence(
            date: heartRate[0].date,
            sport: .running,
            heartRateSamples: heartRate.map {
                HeartRateReading(date: $0.date, beatsPerMinute: $0.value)
            }
        )

        guard let breakdown = WorkoutIntelligence.zoneBreakdown(
            for: evidence,
            maximumHeartRate: ceiling.maximum,
            source: ceiling.source
        ) else {
            return .failure(.noHeartRateSamples)
        }
        return .success(breakdown)
    }
}

extension HeartRateZoneResolver.Unavailable {
    var message: String {
        switch self {
        case .noHeartRateSamples:
            "Health holds no heart-rate samples for this session."
        case .noCeiling:
            "Add your date of birth in Settings → Training to see zones."
        }
    }
}
