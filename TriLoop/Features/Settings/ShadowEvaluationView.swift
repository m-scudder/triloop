#if DEBUG
import SwiftData
import SwiftUI

/// §51's non-authoritative second opinion, for inspection only.
///
/// §52: the existing engine remains the source of every training decision.
/// Nothing on this screen is wired into progression — it exists so the signals
/// can be judged against the engine before any future phase acts on them.
struct ShadowEvaluationView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Query private var profiles: [AthleteProfile]
    @Query private var summaries: [ImportedWorkoutSummary]
    @Environment(\.healthProvider) private var health

    @State private var recovery: [RecoveryMetricKey: [RecoveryReading]] = [:]
    @State private var interpreted: [TrainingIntelligenceBuilder.Interpreted] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading recovery data…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                let signals = buildSignals()
                let observation = ShadowEvaluator.evaluate(
                    signals: signals,
                    engineDecision: engineDecision
                )

                comparison(observation)
                workload(signals.workload)
                recoverySection(signals.recovery)
            }
        }
        .navigationTitle("Shadow evaluation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRecovery() }
    }

    private func comparison(_ observation: ShadowObservation) -> some View {
        Section {
            LabeledContent("Current engine", value: observation.engineDecision)
            LabeledContent("Shadow", value: label(for: observation.suggestion))

            ForEach(observation.reasons, id: \.self) { reason in
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Comparison")
        } footer: {
            Text("Observation only. The current engine decides every training change; nothing here affects your plan.")
        }
    }

    private func workload(_ signals: WorkloadSignals) -> some View {
        Section("Workload") {
            row("This week", signals.currentWeek.value.map { "\(Int($0.rounded()))" })
            row("Last week", signals.previousWeek.value.map { "\(Int($0.rounded()))" })
            row("4-week average", signals.fourWeekAverage.value.map { "\(Int($0.rounded()))" })
            row(
                "Change vs last week",
                signals.weekOnWeekChange.map { "\($0 > 0 ? "+" : "")\(Int(($0 * 100).rounded()))%" }
            )
        }
    }

    private func recoverySection(_ signals: RecoverySignals) -> some View {
        Section("Recovery") {
            if signals.isEmpty {
                Text("No recovery baselines yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(RecoveryMetricKey.allCases, id: \.self) { metric in
                    if let standing = signals.standings[metric] {
                        row(metric.rawValue, standing.rawValue)
                    }
                }
            }
        }
    }

    private func row(_ name: String, _ value: String?) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value ?? "Unavailable")
                .foregroundStyle(value == nil ? .secondary : .primary)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func label(for suggestion: ShadowObservation.Suggestion) -> String {
        switch suggestion {
        case .agrees: "Agrees"
        case .maintainMayBeMoreAppropriate: "Maintain may be more appropriate"
        case .reduceMayBeMoreAppropriate: "Reduce may be more appropriate"
        case .insufficientEvidence: "Insufficient evidence"
        }
    }

    /// What the authoritative engine concluded for the latest week.
    private var engineDecision: String {
        plans.last?.generationReasonCode?.rawValue ?? "unknown"
    }

    private func buildSignals() -> TrainingSignals {
        let builder = TrainingIntelligenceBuilder(
            birthDate: profiles.first?.setup?.birthDate,
            observedMaximumHeartRate: summaries.compactMap(\.maximumHeartRate).max()
        )
        return TrainingSignalsBuilder.build(
            weeks: builder.weeks(from: plans, interpreted: interpreted),
            adherence: builder.adherence(from: interpreted),
            recovery: recovery,
            asOf: .now
        )
    }

    private func loadRecovery() async {
        defer { isLoading = false }

        let builder = TrainingIntelligenceBuilder(
            birthDate: profiles.first?.setup?.birthDate,
            observedMaximumHeartRate: summaries.compactMap(\.maximumHeartRate).max()
        )
        interpreted = builder.interpret(await builder.evidence(in: plans, provider: health))

        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -28, to: end) else { return }

        var collected: [RecoveryMetricKey: [RecoveryReading]] = [:]
        for metric in RecoveryMetric.allCases {
            guard let key = RecoveryMetricKey(rawValue: metric.rawValue) else { continue }
            let points = (try? await health.recoverySeries(metric, from: start, to: end)) ?? []
            guard !points.isEmpty else { continue }
            collected[key] = points.map { RecoveryReading(date: $0.date, value: $0.value) }
        }
        recovery = collected
    }
}
#endif
