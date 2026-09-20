import SwiftUI

/// Recovery gets its own Progress destination so the athlete can read the
/// latest physiological signals without opening disclosures or mixing them with
/// training-load analytics.
struct ProgressRecoveryView: View {
    @Environment(\.healthProvider) private var health
    @State private var readings: [RecoveryMetric: [RecoveryReading]] = [:]
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(text: "Recent signals")

            Card {
                if !isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    RecoverySection(readings: readings, asOf: .now)
                }
            }

            Text("Compared with your own recent baseline. These are observations, not a readiness score.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await loadRecovery() }
    }

    private func loadRecovery() async {
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -28, to: end) else {
            isLoaded = true
            return
        }

        var collected: [RecoveryMetric: [RecoveryReading]] = [:]
        for metric in RecoveryMetric.allCases {
            let points = (try? await health.recoverySeries(metric, from: start, to: end)) ?? []
            collected[metric] = points.map { RecoveryReading(date: $0.date, value: $0.value) }
        }
        readings = collected
        isLoaded = true
    }
}

/// Resting heart rate, HRV and sleep against the athlete's own recent range.
///
/// Every line here is an observation. Nothing on this screen tells the athlete
/// they are overtrained, under-recovered, or unwell.
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
        VStack(alignment: .leading, spacing: 14) {
            if Self.shown.allSatisfy({ (readings[$0] ?? []).isEmpty }) {
                UnavailableNote(text: "No recovery data from Apple Health yet.")
            } else {
                VStack(spacing: 14) {
                    ForEach(Self.shown, id: \.self) { metric in
                        row(for: metric)
                    }
                }
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
                        .font(.subheadline.weight(.medium))
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
