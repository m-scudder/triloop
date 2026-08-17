import SwiftUI

/// What was actually recorded, led by the headline figure.
///
/// A finished session should read as something achieved rather than a table of
/// readings, so the number that matters for that sport is set large and the rest
/// supports it. Missing metrics are omitted rather than shown as zero, which
/// would read as a real measurement.
struct RecordedWorkoutView: View {
    let workout: PlannedWorkout
    let summary: ImportedWorkoutSummary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Completed")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(summary.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                    Text(subheadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                completionBar

                if !supportingStats.isEmpty {
                    Divider()

                    HStack(alignment: .top, spacing: 8) {
                        ForEach(supportingStats, id: \.label) { stat in
                            StatTile(value: stat.value, label: stat.label)
                        }
                    }
                }
            }
        }
    }

    private var completionBar: some View {
        let ratio = workout.recordedCompletion

        return VStack(alignment: .leading, spacing: 4) {
            ProportionBar(fraction: ratio, tint: ratio >= 0.9 ? .green : .orange)
            Text(ratio >= 1
                 ? "Full session completed"
                 : "\(Int((ratio * 100).rounded()))% of the planned session")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The figure that defines the session: distance for swimming, time for the
    /// rest, since that is how each is prescribed.
    private var headline: String {
        if workout.discipline == .swimming, let distance = summary.distanceMeters, distance > 0 {
            return TrainingFormatter.distance(meters: distance)
        }
        return TrainingFormatter.totalDuration(seconds: summary.duration)
    }

    private var subheadline: String {
        if workout.discipline == .swimming {
            return TrainingFormatter.totalDuration(seconds: summary.duration)
        }
        if let distance = summary.distanceMeters, distance > 0 {
            return TrainingFormatter.distance(meters: distance)
        }
        return workout.title
    }

    private var supportingStats: [(label: String, value: String)] {
        var stats: [(String, String)] = []

        if let continuous = summary.longestContinuousSwimMeters {
            stats.append(("Non-stop", TrainingFormatter.distance(meters: continuous)))
        }
        if let lengths = summary.swimmingLengths {
            stats.append(("Lengths", "\(lengths)"))
        }
        if let average = summary.averageHeartRate {
            stats.append(("Avg bpm", "\(Int(average.rounded()))"))
        }
        if let maximum = summary.maximumHeartRate, summary.longestContinuousSwimMeters == nil {
            stats.append(("Max bpm", "\(Int(maximum.rounded()))"))
        }
        if let elevation = summary.elevationAscendedMeters {
            stats.append(("Ascent", TrainingFormatter.distance(meters: elevation)))
        }

        // Four tiles is as many as fit before the numbers start shrinking.
        return Array(stats.prefix(4))
    }
}
