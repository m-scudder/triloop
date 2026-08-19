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

        let calculator = HeartRateZoneCalculator(
            maximumHeartRate: ceiling.maximum,
            source: ceiling.source
        )
        let readings = heartRate.map {
            HeartRateReading(date: $0.date, beatsPerMinute: $0.value)
        }

        guard let breakdown = calculator.breakdown(from: readings) else {
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
