import Charts
import SwiftUI

/// Square summary of one metric, with a preview of its shape.
///
/// The preview is axis-free on purpose: at this size the shape is legible but
/// individual values are not, so drawing a scale would imply precision the card
/// cannot deliver.
struct MetricCard: View {
    let metric: WorkoutMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: metric.symbol)
                    .font(.caption)
                Text(metric.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(metric.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.headline)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(metric.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            preview
                .frame(height: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(metric.tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(metric.tint.opacity(0.18), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title), \(metric.headline) \(metric.caption)")
    }

    @ViewBuilder
    private var preview: some View {
        switch metric.kind {
        case .swimLengths:
            Chart(metric.lengths) { length in
                BarMark(
                    x: .value("Length", length.index),
                    y: .value("Seconds", length.seconds)
                )
                .foregroundStyle(metric.tint)
                .cornerRadius(1)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)

        case .heartRate:
            Chart(metric.points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(metric.gradient.opacity(0.35))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(metric.tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: previewDomain)

        default:
            Chart(metric.points) { point in
                BarMark(
                    x: .value("Time", point.date, unit: .minute),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(metric.tint)
                .cornerRadius(1)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }

    /// Trimmed to the range actually used, so a resting-to-peak axis does not
    /// flatten the line into a straight bar.
    private var previewDomain: ClosedRange<Double> {
        let values = metric.points.map(\.value)
        let low = (values.min() ?? 0) - 4
        let high = (values.max() ?? 1) + 4
        return max(low, 0)...max(high, low + 1)
    }
}
