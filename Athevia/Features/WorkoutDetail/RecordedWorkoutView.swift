import SwiftUI

/// Dense recorded-workout summary. Its information hierarchy mirrors the
/// familiar two-column workout summary layout while all visual treatment stays
/// inside Athevia's design system.
struct RecordedWorkoutView: View {
    let workout: PlannedWorkout
    let summary: ImportedWorkoutSummary

    var body: some View {
        Card {
            VStack(spacing: 0) {
                summaryRow(
                    left: metric("Workout Time", TrainingFormatter.totalDuration(seconds: summary.duration)),
                    right: metric("Distance", distance)
                )

                Divider()

                summaryRow(
                    left: metric("Active Calories", activeCalories),
                    right: metric("Total Calories", totalCalories)
                )

                Divider()

                summaryRow(
                    left: averageMetric,
                    right: metric("Avg Heart Rate", averageHeartRate)
                )
            }
        }
    }

    private func summaryRow(left: SummaryMetric, right: SummaryMetric) -> some View {
        HStack(alignment: .top, spacing: 28) {
            metricCell(left)
            metricCell(right)
        }
        .padding(.vertical, 18)
    }

    private func metricCell(_ metric: SummaryMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.label)
                .font(.subheadline)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))

            Text(metric.value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ label: String, _ value: String?) -> SummaryMetric {
        SummaryMetric(label: label, value: value ?? "—")
    }

    private var distance: String? {
        guard let meters = summary.distanceMeters, meters > 0 else { return nil }
        return TrainingFormatter.distance(meters: meters)
    }

    private var activeCalories: String? {
        guard let calories = summary.metrics?.activeEnergyKilocalories else { return nil }
        return "\(Int(calories.rounded())) kcal"
    }

    /// HealthKit currently imports active energy for workouts, but not basal
    /// energy attributable to the workout interval. Do not invent a total.
    private var totalCalories: String? {
        nil
    }

    private var averageHeartRate: String? {
        guard let heartRate = summary.averageHeartRate else { return nil }
        return "\(Int(heartRate.rounded())) bpm"
    }

    private var averageMetric: SummaryMetric {
        guard let distance = summary.distanceMeters,
              distance > 0,
              summary.duration > 0 else {
            return metric(averageMetricLabel, nil)
        }

        switch workout.discipline.sport {
        case .running:
            let secondsPerKm = Int((summary.duration / (distance / 1_000)).rounded())
            return metric(
                "Avg Pace",
                String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
            )

        case .cycling:
            return metric(
                "Avg Speed",
                String(format: "%.1f km/h", distance / summary.duration * 3.6)
            )

        case .swimming:
            return metric(
                "Avg Pace",
                TrainingFormatter.swimPace(secondsPer100m: summary.duration / (distance / 100))
            )

        case nil:
            return metric("Avg Speed", nil)
        }
    }

    private var averageMetricLabel: String {
        switch workout.discipline.sport {
        case .running, .swimming: "Avg Pace"
        case .cycling, nil: "Avg Speed"
        }
    }
}

private struct SummaryMetric {
    let label: String
    let value: String
}
