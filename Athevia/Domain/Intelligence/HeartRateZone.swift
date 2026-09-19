import Foundation

/// What the zone boundaries were anchored to.
///
/// §28 anticipated a HealthKit-native zone API. There is none: nothing matching
/// `HeartRateZone` exists in the SDK, and Apple Fitness computes zones
/// privately. Every breakdown is therefore derived here, and these cases name
/// what actually set the ceiling.
enum HeartRateZoneSource: String, Sendable {
    /// From the athlete's stated date of birth, via 220 − age.
    case ageBasedMaximum
    /// From the hardest effort in the athlete's own history.
    case observedMaximum
}

/// One heart-rate reading, independent of where it was measured.
///
/// Declared here rather than reusing `SamplePoint` so the intelligence layer
/// does not depend on the data layer.
struct HeartRateReading: Equatable, Sendable {
    let date: Date
    let beatsPerMinute: Double

    init(date: Date, beatsPerMinute: Double) {
        self.date = date
        self.beatsPerMinute = beatsPerMinute
    }
}

/// Time spent in one zone.
struct HeartRateZone: Equatable, Sendable, Identifiable {
    /// 1 through 5, in the conventional order.
    let number: Int
    let lowerBoundBPM: Double
    /// Nil for the top zone, which is open-ended.
    let upperBoundBPM: Double?
    let duration: TimeInterval

    var id: Int { number }
}

/// A whole session's time in zone.
struct HeartRateZoneBreakdown: Equatable, Sendable {
    let zones: [HeartRateZone]
    let source: HeartRateZoneSource

    var totalDuration: TimeInterval {
        zones.reduce(0) { $0 + $1.duration }
    }

    /// Derived rather than stored, so percentages cannot drift out of step with
    /// the durations they describe.
    func share(of zone: HeartRateZone) -> Double {
        totalDuration > 0 ? zone.duration / totalDuration : 0
    }
}
