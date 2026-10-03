import SwiftUI

/// Prominent summary of the workout that was actually recorded.
///
/// This intentionally uses Athevia's existing adaptive colours. The two-column
/// layout is inspired by the compact information hierarchy of Apple's workout
/// summary without copying its colour treatment.
struct RecordedWorkoutView: View {
    @Environment(\.atheviaTheme) private var theme

    let workout: PlannedWorkout
    let summary: ImportedWorkoutSummary

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading)
    ]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Label("Completed", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AtheviaAdaptiveStyle(.green, gaming: .success))

                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.element.label) { index, metric in
                        metricCell(metric)
                            .padding(.vertical, 14)

                        if index < metrics.count - 2 {
                            Divider()
                                .gridCellUnsizedAxes(.horizontal)
                        }
                    }
                }

                completionBar
            }
        }
    }

    private func metricCell(_ metric: SummaryMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label)
                .font(.subheadline)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            Text(metric.value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var completionBar: some View {
        let ratio = workout.recordedCompletion

        return VStack(alignment: .leading, spacing: 4) {
            ProportionBar(fraction: ratio, tint: ratio >= 0.9 ? .green : .orange)
            Text(ratio >= 1
                 ? "Full session completed"
                 : "\(Int((ratio * 100).rounded()))% of the planned session")
                .font(.caption)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
    }

    private var metrics: [SummaryMetric] {
        var result = [
            SummaryMetric(
                label: "Workout time",
                value: TrainingFormatter.totalDuration(seconds: summary.duration)
            )
        ]

        if let distance = summary.distanceMeters, distance > 0 {
            result.append(
                SummaryMetric(
                    label: "Distance",
                    value: TrainingFormatter.distance(meters: distance)
                )
            )
        }

        if let calories = summary.metrics?.activeEnergyKilocalories {
            result.append(
                SummaryMetric(
                    label: "Active calories",
                    value: "\(Int(calories.rounded())) kcal"
                )
            )
        }

        if let average = averageSpeedOrPace {
            result.append(average)
        }

        if let heartRate = summary.averageHeartRate {
            result.append(
                SummaryMetric(
                    label: "Avg heart rate",
                    value: "\(Int(heartRate.rounded())) bpm"
                )
            )
        }

        if let maximum = summary.maximumHeartRate {
            result.append(
                SummaryMetric(
                    label: "Max heart rate",
                    value: "\(Int(maximum.rounded())) bpm"
                )
            )
        }

        return result
    }

    private var averageSpeedOrPace: SummaryMetric? {
        guard let distance = summary.distanceMeters,
              distance > 0,
              summary.duration > 0 else {
            return nil
        }

        switch workout.discipline.sport {
        case .running:
            let secondsPerKm = Int((summary.duration / (distance / 1_000)).rounded())
            return SummaryMetric(
                label: "Avg pace",
                value: String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
            )

        case .cycling:
            return SummaryMetric(
                label: "Avg speed",
                value: String(format: "%.1f km/h", distance / summary.duration * 3.6)
            )

        case .swimming:
            return SummaryMetric(
                label: "Avg pace",
                value: TrainingFormatter.swimPace(
                    secondsPer100m: summary.duration / (distance / 100)
                )
            )

        case nil:
            return nil
        }
    }
}

private struct SummaryMetric {
    let label: String
    let value: String
}
