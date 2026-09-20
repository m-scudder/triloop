import Foundation

/// One point in a workout's time series.
struct SamplePoint: Equatable, Sendable, Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

/// One pool length, with the pace it was swum at.
struct SwimLengthPoint: Equatable, Sendable, Identifiable {
    let index: Int
    let start: Date
    let seconds: TimeInterval
    let meters: Double
    /// True when a rest preceded this length, which is what breaks a set up.
    let followedRest: Bool

    var id: Int { index }

    /// Seconds per 100 m, the unit swimmers actually compare.
    var pacePer100m: Double {
        meters > 0 ? seconds / meters * 100 : 0
    }
}

/// Detail behind a completed workout, fetched on demand.
///
/// Deliberately not persisted: HealthKit already holds it, and storing a copy of
/// every sample would duplicate a lot of data for a screen that is opened
/// occasionally.
struct WorkoutSamples: Equatable, Sendable {
    var heartRate: [SamplePoint] = []
    /// Cadence in steps per minute, bucketed per minute.
    var cadence: [SamplePoint] = []
    /// Distance covered per minute, which reads as effort over time.
    var distancePerMinute: [SamplePoint] = []
    /// Active energy per minute. The one metric every activity type records,
    /// including strength work that has no distance or pace.
    var energy: [SamplePoint] = []
    var swimLengths: [SwimLengthPoint] = []

    var isEmpty: Bool {
        heartRate.isEmpty && cadence.isEmpty && distancePerMinute.isEmpty
            && energy.isEmpty && swimLengths.isEmpty
    }

    var averageHeartRate: Double? {
        guard !heartRate.isEmpty else { return nil }
        return heartRate.reduce(0) { $0 + $1.value } / Double(heartRate.count)
    }

    var peakHeartRate: Double? {
        heartRate.map(\.value).max()
    }
}
