import Charts
import SwiftUI

/// Time-series detail for a completed workout.
///
/// Each chart is coloured by what it measures rather than by a single app
/// accent: heart rate runs cool to hot, pace runs fast to slow, and volume takes
/// the sport's own hue. The colour therefore carries meaning instead of decoration.
struct WorkoutChartsView: View {
    let discipline: Discipline
    let samples: WorkoutSamples

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !samples.heartRate.isEmpty {
                heartRateChart
            }
            if !samples.swimLengths.isEmpty {
                swimLengthChart
            }
            if !samples.cadence.isEmpty, discipline == .running {
                cadenceChart
            }
            if !samples.distancePerMinute.isEmpty, discipline != .swimming {
                distanceChart
            }
        }
    }

    // MARK: Heart rate

    private var heartRateChart: some View {
        chartSection(
            title: "Heart rate",
            detail: heartRateDetail
        ) {
            Chart(samples.heartRate) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(heartRateGradient.opacity(0.28))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(heartRateGradient)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: heartRateDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
    }

    /// Cool at easy effort through to hot at hard effort, so the shape of the
    /// session is readable without consulting the axis.
    private var heartRateGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.62, blue: 0.98),
                Color(red: 0.20, green: 0.80, blue: 0.55),
                Color(red: 1.00, green: 0.72, blue: 0.15),
                Color(red: 0.95, green: 0.26, blue: 0.21)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var heartRateDomain: ClosedRange<Double> {
        let values = samples.heartRate.map(\.value)
        let low = (values.min() ?? 60) - 8
        let high = (values.max() ?? 160) + 8
        return max(low, 40)...high
    }

    private var heartRateDetail: String? {
        guard let average = samples.averageHeartRate, let peak = samples.peakHeartRate else { return nil }
        return "avg \(Int(average.rounded())) · peak \(Int(peak.rounded())) bpm"
    }

    // MARK: Swimming

    private var swimLengthChart: some View {
        chartSection(
            title: "Lengths",
            detail: "\(samples.swimLengths.count) × \(Int(samples.swimLengths.first?.meters ?? 25)) m · bars show pace"
        ) {
            Chart(samples.swimLengths) { length in
                BarMark(
                    x: .value("Length", length.index),
                    y: .value("Seconds", length.seconds)
                )
                .foregroundStyle(paceColour(for: length))
                .cornerRadius(3)

                // A rest breaks the set, which is what continuous swimming is judged on.
                if length.followedRest {
                    RuleMark(x: .value("Length", length.index))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6))
            }
        }
    }

    /// Green for the quickest length through to orange for the slowest, scaled
    /// to this session rather than an absolute standard.
    private func paceColour(for length: SwimLengthPoint) -> Color {
        let paces = samples.swimLengths.map(\.pacePer100m)
        guard let fastest = paces.min(), let slowest = paces.max(), slowest > fastest else {
            return Discipline.swimming.tint
        }
        let position = (length.pacePer100m - fastest) / (slowest - fastest)
        return Color(
            hue: 0.38 - (0.30 * position),
            saturation: 0.75,
            brightness: 0.85
        )
    }

    // MARK: Running and cycling

    private var cadenceChart: some View {
        chartSection(title: "Cadence", detail: "steps per minute") {
            Chart(samples.cadence) { point in
                BarMark(
                    x: .value("Time", point.date, unit: .minute),
                    y: .value("Steps", point.value)
                )
                .foregroundStyle(discipline.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
    }

    private var distanceChart: some View {
        chartSection(title: "Distance per minute", detail: nil) {
            Chart(samples.distancePerMinute) { point in
                BarMark(
                    x: .value("Time", point.date, unit: .minute),
                    y: .value("Metres", point.value)
                )
                .foregroundStyle(discipline.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
    }

    // MARK: Shared

    private func chartSection<Content: View>(
        title: String,
        detail: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionEyebrow(text: title)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Card {
                content()
                    .frame(height: 140)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                    }
            }
        }
    }
}
