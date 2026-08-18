import SwiftUI

/// One measurable aspect of a completed session.
///
/// Built from whatever HealthKit actually returned, so a pool swim offers
/// lengths and a ride offers pace, without either screen having to ask what
/// sport it is looking at.
struct WorkoutMetric: Identifiable {
    enum Kind: String {
        case heartRate
        case cadence
        case distance
        case swimLengths
    }

    let kind: Kind
    let title: String
    let headline: String
    let caption: String
    let symbol: String
    let points: [SamplePoint]
    let lengths: [SwimLengthPoint]
    let tint: Color

    var id: String { kind.rawValue }

    /// Heart rate reads cool to hot; everything else takes the sport's hue, so
    /// colour always means the same thing across a session.
    var gradient: LinearGradient {
        kind == .heartRate
            ? LinearGradient(colors: WorkoutMetric.heatColours, startPoint: .bottom, endPoint: .top)
            : LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .bottom, endPoint: .top)
    }

    static let heatColours: [Color] = [
        Color(red: 0.16, green: 0.62, blue: 0.98),
        Color(red: 0.20, green: 0.80, blue: 0.55),
        Color(red: 1.00, green: 0.72, blue: 0.15),
        Color(red: 0.95, green: 0.26, blue: 0.21)
    ]
}

extension WorkoutMetric {
    static func all(for discipline: Discipline, samples: WorkoutSamples) -> [WorkoutMetric] {
        var metrics: [WorkoutMetric] = []
        let tint = discipline.tint

        if !samples.heartRate.isEmpty, let average = samples.averageHeartRate {
            metrics.append(
                WorkoutMetric(
                    kind: .heartRate,
                    title: "Heart rate",
                    headline: "\(Int(average.rounded()))",
                    caption: samples.peakHeartRate.map { "avg bpm · peak \(Int($0.rounded()))" } ?? "avg bpm",
                    symbol: "heart.fill",
                    points: samples.heartRate,
                    lengths: [],
                    tint: Color(red: 0.95, green: 0.26, blue: 0.21)
                )
            )
        }

        if !samples.swimLengths.isEmpty {
            let fastest = samples.swimLengths.map(\.seconds).min() ?? 0
            metrics.append(
                WorkoutMetric(
                    kind: .swimLengths,
                    title: "Lengths",
                    headline: "\(samples.swimLengths.count)",
                    caption: "best \(Int(fastest))s",
                    symbol: "figure.pool.swim",
                    points: [],
                    lengths: samples.swimLengths,
                    tint: tint
                )
            )
        }

        if !samples.cadence.isEmpty, discipline == .running {
            let average = samples.cadence.reduce(0) { $0 + $1.value } / Double(samples.cadence.count)
            metrics.append(
                WorkoutMetric(
                    kind: .cadence,
                    title: "Cadence",
                    headline: "\(Int(average.rounded()))",
                    caption: "avg steps / min",
                    symbol: "shoeprints.fill",
                    points: samples.cadence,
                    lengths: [],
                    tint: tint
                )
            )
        }

        if !samples.distancePerMinute.isEmpty, discipline != .swimming {
            let total = samples.distancePerMinute.reduce(0) { $0 + $1.value }
            let perMinute = total / Double(max(samples.distancePerMinute.count, 1))
            metrics.append(
                WorkoutMetric(
                    kind: .distance,
                    title: "Pace",
                    headline: TrainingFormatter.distance(meters: perMinute),
                    caption: "per minute",
                    symbol: "speedometer",
                    points: samples.distancePerMinute,
                    lengths: [],
                    tint: tint
                )
            )
        }

        return metrics
    }
}
