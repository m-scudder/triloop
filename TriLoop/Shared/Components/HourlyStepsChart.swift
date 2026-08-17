import Charts
import SwiftUI

/// Steps through the day, one bar per hour.
///
/// Bars deepen with volume so the shape of the day is legible at a glance,
/// without needing an axis or a target line.
struct HourlyStepsChart: View {
    let points: [SamplePoint]

    private var peak: Double {
        max(points.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Hour", point.date, unit: .hour),
                y: .value("Steps", point.value)
            )
            .foregroundStyle(colour(for: point.value))
            .cornerRadius(2)
        }
        .frame(height: 90)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) {
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .accessibilityLabel("Steps by hour")
    }

    private func colour(for value: Double) -> Color {
        let share = value / peak
        return Color(
            hue: 0.58 - (0.14 * share),
            saturation: 0.30 + (0.55 * share),
            brightness: 0.55 + (0.40 * share)
        )
    }
}
