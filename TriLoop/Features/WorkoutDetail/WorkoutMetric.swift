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
        case steps
        case energy
        case distance
        case swimLengths
        case swimPace
    }

    let kind: Kind
    let title: String
    let headline: String
    let caption: String
    let symbol: String
    let points: [SamplePoint]
    let lengths: [SwimLengthPoint]
    let tint: Color
    /// Kept beside the formatted headline so the detail screen can restate
    /// HealthKit's figures instead of recomputing them from the buckets.
    var average: Double? = nil
    var peak: Double? = nil

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
    /// A nil discipline means an activity TriLoop does not train. Those still
    /// get everything HealthKit recorded — only the sport-specific readings
    /// (pace, cadence) are withheld, because they would be inventing meaning
    /// the numbers do not carry.
    static func all(
        for discipline: Discipline?,
        samples: WorkoutSamples,
        summary: ImportedWorkoutSummary? = nil
    ) -> [WorkoutMetric] {
        var metrics: [WorkoutMetric] = []
        let tint = discipline?.tint ?? .secondary

        // HealthKit averages every sample it holds; the series here is bucketed
        // to one point a minute, so averaging it again gives a different figure.
        let average = summary?.averageHeartRate ?? samples.averageHeartRate
        let peak = summary?.maximumHeartRate ?? samples.peakHeartRate

        if !samples.heartRate.isEmpty, let average {
            metrics.append(
                WorkoutMetric(
                    kind: .heartRate,
                    title: "Heart rate",
                    headline: "\(Int(average.rounded()))",
                    caption: peak.map { "avg bpm · peak \(Int($0.rounded()))" } ?? "avg bpm",
                    symbol: "heart.fill",
                    points: samples.heartRate,
                    lengths: [],
                    tint: Color(red: 0.95, green: 0.26, blue: 0.21),
                    average: average,
                    peak: peak
                )
            )
        }

        if !samples.swimLengths.isEmpty {
            let fastest = samples.swimLengths.map(\.seconds).min() ?? 0
            let sets = samples.swimLengths.filter(\.followedRest).count + 1
            metrics.append(
                WorkoutMetric(
                    kind: .swimLengths,
                    title: "Lengths",
                    headline: "\(samples.swimLengths.count)",
                    caption: "\(sets) set\(sets == 1 ? "" : "s") · best \(Int(fastest))s",
                    symbol: "figure.pool.swim",
                    points: [],
                    lengths: samples.swimLengths,
                    tint: tint
                )
            )

            let distance = samples.swimLengths.reduce(0) { $0 + $1.meters }
            let seconds = samples.swimLengths.reduce(0) { $0 + $1.seconds }
            if distance > 0 {
                metrics.append(
                    WorkoutMetric(
                        kind: .swimPace,
                        title: "Pace",
                        headline: TrainingFormatter.swimPace(secondsPer100m: seconds / distance * 100),
                        caption: "/ 100 m · rests excluded",
                        symbol: "speedometer",
                        points: [],
                        lengths: samples.swimLengths,
                        tint: tint
                    )
                )
            }
        } else if discipline == .swimming, !samples.distancePerMinute.isEmpty {
            // Open water has no lap events, so pace comes from the distance
            // series instead. That is elapsed pace: there is no way to tell a
            // rest from slow swimming without lengths.
            let distance = samples.distancePerMinute.reduce(0) { $0 + $1.value }
            let seconds = Double(samples.distancePerMinute.count) * 60

            if distance > 0 {
                metrics.append(
                    WorkoutMetric(
                        kind: .swimPace,
                        title: "Pace",
                        headline: TrainingFormatter.swimPace(secondsPer100m: seconds / distance * 100),
                        caption: "/ 100 m · elapsed",
                        symbol: "speedometer",
                        points: samples.distancePerMinute,
                        lengths: [],
                        tint: tint
                    )
                )
            }
        }

        if !samples.cadence.isEmpty, discipline == .running {
            let average = samples.cadence.reduce(0) { $0 + $1.value } / Double(samples.cadence.count)
            metrics.append(
                WorkoutMetric(
                    kind: .cadence,
                    title: "Cadence",
                    headline: "\(Int((summary?.metrics?.averageCadence ?? average).rounded()))",
                    caption: "avg steps / min",
                    symbol: "shoeprints.fill",
                    points: samples.cadence,
                    lengths: [],
                    tint: tint
                )
            )
        } else if !samples.cadence.isEmpty, discipline == nil {
            // Steps during strength work are movement, not cadence: calling it
            // cadence would imply a running rhythm that isn't being measured.
            let total = samples.cadence.reduce(0) { $0 + $1.value }
            if total > 0 {
                metrics.append(
                    WorkoutMetric(
                        kind: .steps,
                        title: "Steps",
                        headline: "\(Int(total.rounded()))",
                        caption: "total during session",
                        symbol: "shoeprints.fill",
                        points: samples.cadence,
                        lengths: [],
                        tint: tint
                    )
                )
            }
        }

        if !samples.energy.isEmpty {
            let total = samples.energy.reduce(0) { $0 + $1.value }
            if total > 0 {
                metrics.append(
                    WorkoutMetric(
                        kind: .energy,
                        title: "Energy",
                        headline: "\(Int(total.rounded()))",
                        caption: "active kcal",
                        symbol: "flame.fill",
                        points: samples.energy,
                        lengths: [],
                        tint: Color(red: 0.98, green: 0.55, blue: 0.15)
                    )
                )
            }
        }

        if !samples.distancePerMinute.isEmpty, let discipline, discipline != .swimming {
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
        } else if !samples.distancePerMinute.isEmpty, discipline == nil {
            // Reported as a total rather than a pace: distance covered while
            // lifting is incidental, and a pace would read as a performance.
            let total = samples.distancePerMinute.reduce(0) { $0 + $1.value }
            if total > 0 {
                metrics.append(
                    WorkoutMetric(
                        kind: .distance,
                        title: "Distance",
                        headline: TrainingFormatter.distance(meters: total),
                        caption: "covered during session",
                        symbol: "point.topleft.down.curvedto.point.bottomright.up",
                        points: samples.distancePerMinute,
                        lengths: [],
                        tint: tint
                    )
                )
            }
        }

        return metrics
    }
}
