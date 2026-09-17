import SwiftUI

/// Objective planned-versus-actual execution. Subjective effort is intentionally
/// kept in the athlete's report, where planned and reported effort have context.
struct SessionExecutionView: View {
    let outcome: ExecutionComparison.Outcome
    let plannedSeconds: TimeInterval?
    let actualSeconds: TimeInterval?
    // Retained for call-site compatibility; effort is presented separately.
    let targetRPE: RPERange?
    let reportedRPE: Int?

    var body: some View {
        // Do not render a comparison shell unless there is an objective value
        // on both sides. This avoids orphaned "Planned / Actual" headings for
        // sessions whose overall result came only from reported effort.
        if hasDurationComparison {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionEyebrow(text: "Session execution")
                    Spacer()
                    InfoButton(concept: .plannedVsActual)
                }

                VStack(spacing: 8) {
                    headerRow
                    row(
                        "Duration",
                        planned: plannedSeconds.map { TrainingFormatter.totalDuration(seconds: $0) },
                        actual: actualSeconds.map { TrainingFormatter.totalDuration(seconds: $0) }
                    )
                }
            }
        }
    }

    private var hasDurationComparison: Bool {
        outcome.duration != nil && plannedSeconds != nil && actualSeconds != nil
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
}
