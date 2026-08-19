import SwiftUI

/// The §32 planned-versus-actual table.
///
/// Shows the two figures side by side and one named result, so the athlete can
/// see the evidence rather than being handed a verdict.
struct SessionExecutionView: View {
    let outcome: ExecutionComparison.Outcome
    let plannedSeconds: TimeInterval?
    let actualSeconds: TimeInterval?
    let targetRPE: RPERange?
    let reportedRPE: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Session execution")

            VStack(spacing: 8) {
                headerRow

                if outcome.duration != nil {
                    row(
                        "Duration",
                        planned: plannedSeconds.map { TrainingFormatter.totalDuration(seconds: $0) },
                        actual: actualSeconds.map { TrainingFormatter.totalDuration(seconds: $0) }
                    )
                }

                if outcome.effort != nil {
                    row(
                        "Effort",
                        planned: targetRPE.map { $0.lower == $0.upper ? "\($0.lower)/10" : "\($0.lower)–\($0.upper)/10" },
                        actual: reportedRPE.map { "\($0)/10" }
                    )
                }
            }

            HStack {
                Text(outcome.overall.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tint)
                Spacer()
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Planned")
                .frame(width: 80, alignment: .trailing)
            Text("Actual")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func row(_ name: String, planned: String?, actual: String?) -> some View {
        HStack {
            Text(name)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(planned ?? "—")
                .frame(width: 80, alignment: .trailing)
            Text(actual ?? "—")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.subheadline)
        .monospacedDigit()
    }

    /// Above target reads as caution rather than achievement: it usually means
    /// an easy session was not easy.
    private var tint: Color {
        switch outcome.overall {
        case .withinTarget: .green
        case .aboveTarget, .incomplete: .orange
        case .belowTarget, .skipped, .missed: .secondary
        }
    }
}
