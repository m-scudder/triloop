import SwiftData
import SwiftUI

/// Post-workout capture. Every control has a sensible default so the athlete
/// can save without answering anything, which is what keeps this to ~10 seconds.
struct FeedbackSheet: View {
    let workout: PlannedWorkout

    @State private var draft = FeedbackDraft()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    effortSection
                    painSection
                    recoverySection
                    notesSection
                }
                .padding(20)
            }
            .navigationTitle("How did that go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
        }
    }

    private var effortSection: some View {
        LabeledSection(title: "Effort") {
            VStack(alignment: .leading, spacing: 10) {
                Text(RPEScale.label(for: draft.rpe))
                    .font(.title3.weight(.medium))
                ScorePicker(
                    range: RPEScale.minimum...RPEScale.maximum,
                    selection: $draft.rpe,
                    accessibilityPrefix: "Effort"
                )
            }
        }
    }

    private var painSection: some View {
        LabeledSection(title: "Pain") {
            VStack(alignment: .leading, spacing: 10) {
                Text(PainScale.label(for: draft.painScore))
                    .font(.title3.weight(.medium))
                ScorePicker(
                    range: PainScale.minimum...PainScale.maximum,
                    selection: $draft.painScore,
                    accessibilityPrefix: "Pain"
                )

                if draft.reportsPain {
                    Text("Where?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ChipGrid(
                        values: PainLocation.allCases,
                        title: \.displayName,
                        isSelected: { draft.painLocations.contains($0) },
                        toggle: { location in
                            if draft.painLocations.contains(location) {
                                draft.painLocations.remove(location)
                            } else {
                                draft.painLocations.insert(location)
                            }
                        }
                    )
                }
            }
            .animation(.snappy, value: draft.reportsPain)
        }
    }

    private var recoverySection: some View {
        LabeledSection(title: "Recovery") {
            ChipGrid(
                values: RecoveryFeeling.allCases,
                title: \.displayName,
                isSelected: { $0 == draft.recoveryFeeling },
                toggle: { draft.recoveryFeeling = $0 }
            )
        }
    }

    private var notesSection: some View {
        LabeledSection(title: "Notes") {
            TextField(
                "Optional",
                text: $draft.notes,
                prompt: Text("Anything worth remembering?"),
                axis: .vertical
            )
            .lineLimit(2...5)
            .textFieldStyle(.plain)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.fill.tertiary)
            )
        }
    }

    private func save() {
        workout.recordCompletion(with: draft)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    FeedbackSheet(workout: PreviewData.workout(.running))
        .modelContainer(PreviewData.container)
}
