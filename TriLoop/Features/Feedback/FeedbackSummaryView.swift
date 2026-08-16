import SwiftUI

/// Read-only recap of a saved report.
struct FeedbackSummaryView: View {
    let feedback: WorkoutFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                metric("Effort", "\(feedback.rpe)", RPEScale.label(for: feedback.rpe))
                metric("Pain", "\(feedback.painScore)", PainScale.label(for: feedback.painScore))
            }

            LabeledContent("Recovery", value: feedback.recoveryFeeling.displayName)
                .font(.subheadline)

            if !feedback.painLocations.isEmpty {
                LabeledContent(
                    "Location",
                    value: feedback.painLocations.map(\.displayName).formatted(.list(type: .and))
                )
                .font(.subheadline)
            }

            if !feedback.notes.isEmpty {
                Text(feedback.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
