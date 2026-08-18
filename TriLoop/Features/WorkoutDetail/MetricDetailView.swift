import Charts
import SwiftUI

/// Full-size chart for a single metric, with the numbers behind it.
struct MetricDetailView: View {
    let metric: WorkoutMetric

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.headline)
                        .font(.system(size: 44, weight: .semibold))
                        .monospacedDigit()
                    Text(metric.caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Card {
                    chart
                        .frame(height: 220)
                }

                if !summaryStats.isEmpty {
                    Card {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(summaryStats, id: \.label) { stat in
                                StatTile(value: stat.value, label: stat.label)
                            }
                        }
                    }
                }

                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var chart: some View {
        switch metric.kind {
        case .swimLengths:
            Chart(metric.lengths) { length in
                BarMark(
                    x: .value("Length", length.index),
                    y: .value("Seconds", length.seconds)
                )
                .foregroundStyle(paceColour(for: length))
                .cornerRadius(3)

                if length.followedRest {
                    RuleMark(x: .value("Length", length.index))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }

        case .swimPace:
            if metric.lengths.isEmpty {
                Chart(metric.points) { point in
                    BarMark(
                        x: .value("Time", point.date, unit: .minute),
                        y: .value("Distance", point.value)
                    )
                    .foregroundStyle(metric.gradient)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
            } else {
                Chart(metric.lengths) { length in
                    LineMark(
                        x: .value("Length", length.index),
                        y: .value("Pace", length.pacePer100m)
                    )
                    .foregroundStyle(metric.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Length", length.index),
                        y: .value("Pace", length.pacePer100m)
                    )
                    .foregroundStyle(metric.tint)
                    .symbolSize(length.followedRest ? 60 : 18)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(TrainingFormatter.swimPace(secondsPer100m: seconds))
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                .chartPlotStyle { $0.clipped() }
            }

        case .heartRate:
            Chart(metric.points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(metric.gradient.opacity(0.28))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("BPM", point.value)
                )
                .foregroundStyle(metric.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
            }
            .chartYScale(domain: heartRateDomain)
            // A y-scale bounds the data, not the drawing: a smoothed curve can
            // still be painted past the axis.
            .chartPlotStyle { $0.clipped() }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }

        default:
            Chart(metric.points) { point in
                BarMark(
                    x: .value("Time", point.date, unit: .minute),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(metric.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
    }

    /// Wall-clock pace across the whole swim, rests included, which is the
    /// convention Apple Health reports.
    private var elapsedSwimPace: Double? {
        guard let first = metric.lengths.first, let last = metric.lengths.last else { return nil }
        let distance = metric.lengths.reduce(0) { $0 + $1.meters }
        let elapsed = last.start.addingTimeInterval(last.seconds).timeIntervalSince(first.start)
        guard distance > 0, elapsed > 0 else { return nil }
        return elapsed / distance * 100
    }

    private var heartRateDomain: ClosedRange<Double> {
        let values = metric.points.map(\.value)
        let low = (values.min() ?? 60) - 8
        let high = (values.max() ?? 160) + 8
        return max(low, 40)...high
    }

    /// Ranked within this session rather than against an absolute standard, so
    /// an easy swim is not rendered entirely as slow.
    private func paceColour(for length: SwimLengthPoint) -> Color {
        let paces = metric.lengths.map(\.pacePer100m)
        guard let fastest = paces.min(), let slowest = paces.max(), slowest > fastest else {
            return metric.tint
        }
        let position = (length.pacePer100m - fastest) / (slowest - fastest)
        return Color(hue: 0.38 - (0.30 * position), saturation: 0.75, brightness: 0.85)
    }

    private var summaryStats: [(label: String, value: String)] {
        switch metric.kind {
        case .heartRate:
            let values = metric.points.map(\.value)
            guard let low = values.min() else { return [] }
            let high = metric.peak ?? values.max() ?? low
            let average = metric.average ?? (values.reduce(0, +) / Double(values.count))
            return [
                ("Low", "\(Int(low.rounded()))"),
                ("Average", "\(Int(average.rounded()))"),
                ("Peak", "\(Int(high.rounded()))")
            ]

        case .swimLengths:
            let seconds = metric.lengths.map(\.seconds)
            guard let fastest = seconds.min(), let slowest = seconds.max() else { return [] }
            let rests = metric.lengths.filter(\.followedRest).count
            return [
                ("Fastest", "\(Int(fastest))s"),
                ("Slowest", "\(Int(slowest))s"),
                ("Rests", "\(rests)")
            ]

        case .swimPace:
            guard !metric.lengths.isEmpty else {
                let distance = metric.points.reduce(0) { $0 + $1.value }
                guard distance > 0 else { return [] }
                return [
                    ("Distance", TrainingFormatter.distance(meters: distance)),
                    ("Time", TrainingFormatter.totalDuration(seconds: Double(metric.points.count) * 60))
                ]
            }
            let paces = metric.lengths.map(\.pacePer100m)
            guard let fastest = paces.min() else { return [] }
            var stats: [(String, String)] = [
                ("Fastest", TrainingFormatter.swimPace(secondsPer100m: fastest))
            ]
            if let elapsed = elapsedSwimPace {
                stats.append(("Elapsed", TrainingFormatter.swimPace(secondsPer100m: elapsed)))
            }
            let distance = metric.lengths.reduce(0) { $0 + $1.meters }
            stats.append(("Distance", TrainingFormatter.distance(meters: distance)))
            return stats

        case .cadence:
            let values = metric.points.map(\.value)
            guard let high = values.max() else { return [] }
            let average = values.reduce(0, +) / Double(values.count)
            return [
                ("Average", "\(Int(average.rounded()))"),
                ("Peak", "\(Int(high.rounded()))")
            ]

        case .distance:
            let total = metric.points.reduce(0) { $0 + $1.value }
            let best = metric.points.map(\.value).max() ?? 0
            return [
                ("Total", TrainingFormatter.distance(meters: total)),
                ("Best minute", TrainingFormatter.distance(meters: best))
            ]
        }
    }

    private var note: String? {
        switch metric.kind {
        case .swimLengths:
            "Bars are coloured fastest to slowest within this swim. Dashed lines mark where you rested."
        case .swimPace:
            metric.lengths.isEmpty
                ? "Open water has no lengths to split on, so this is distance covered each minute and an elapsed pace across the whole swim."
                : "The headline excludes rests, so it reflects how fast you swam. “Elapsed” includes them and is the figure Apple Health shows. Larger points mark the first length after a rest."
        case .heartRate:
            "Sampled once a minute. Colour runs cool at easy effort through to hot at hard effort."
        default:
            nil
        }
    }
}
