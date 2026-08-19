import SwiftUI

/// Resting heart rate, HRV and sleep against the athlete's own recent range.
///
/// §43: every line here is an observation. Nothing on this screen tells the
/// athlete they are overtrained, under-recovered, or unwell.
struct RecoverySection: View {
    let readings: [RecoveryMetric: [RecoveryReading]]
    let asOf: Date

    private static let shown: [RecoveryMetric] = [
        .restingHeartRate,
        .heartRateVariability,
        .sleepDuration,
        .cardioFitness
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Recovery")

            if Self.shown.allSatisfy({ (readings[$0] ?? []).isEmpty }) {
                UnavailableNote(text: "No recovery data from Apple Health yet. Wearing a watch overnight records resting heart rate, HRV and sleep.")
            } else {
                VStack(spacing: 10) {
                    ForEach(Self.shown, id: \.self) { metric in
                        row(for: metric)
                    }
                }

                Text("These are observations, not a verdict on how you are training.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func row(for metric: RecoveryMetric) -> some View {
        let baseline = PhysiologicalBaselinePolicy.baseline(
            from: readings[metric] ?? [],
            window: .sevenDay,
            asOf: asOf
        )

        switch baseline {
        case .available(let value):
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.displayName)
                        .font(.subheadline)
                    if let standing = value.standing(tolerance: value.average * PhysiologicalBaselinePolicy.tolerance) {
                        Text(
                            PhysiologicalBaselinePolicy.describe(
                                standing,
                                metric: metric.displayName,
                                higherIsBetter: metric.higherIsBetter
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(format(value.latest ?? value.average, for: metric))
                        .font(.headline)
                        .monospacedDigit()
                    Text("7-day avg \(format(value.average, for: metric))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

        case .insufficientHistory(let found, let required):
            HStack {
                Text(metric.displayName)
                    .font(.subheadline)
                Spacer()
                Text("\(found) of \(required) readings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .unavailable, .queryFailure:
            EmptyView()
        }
    }

    private func format(_ value: Double, for metric: RecoveryMetric) -> String {
        switch metric {
        case .sleepDuration:
            let hours = Int(value)
            let minutes = Int((value - Double(hours)) * 60)
            return "\(hours)h \(minutes)m"
        case .cardioFitness:
            return String(format: "%.1f", value)
        default:
            return "\(Int(value.rounded())) \(metric.unitLabel)"
        }
    }
}
