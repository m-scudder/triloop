import SwiftUI

/// Objective planned-versus-actual execution. Subjective effort is intentionally
/// kept in the athlete's report, where planned and reported effort have context.
struct SessionExecutionView: View {
    let outcome: ExecutionComparison.Outcome
    let plannedSeconds: TimeInterval?
    let actualSeconds: TimeInterval?
    // Retained for call-site compatibility; effort is presented in Your report.
    let targetRPE: RPERange?
    let reportedRPE: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionEyebrow(text: "Session execution")
                Spacer()
                InfoButton(concept: .plannedVsActual)
            }

            VStack(spacing: 8) {
                headerRow

                if outcome.duration != nil {
                    row(
                        "Duration",
                        planned: plannedSeconds.map { TrainingFormatter.totalDuration(seconds: $0) },
                        actual: actualSeconds.map { TrainingFormatter.totalDuration(seconds: $0) }
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

    private var tint: Color {
        switch outcome.overall {
        case .withinTarget: .green
        case .aboveTarget, .incomplete: .orange
        case .belowTarget, .skipped, .missed: .secondary
        }
    }
}
