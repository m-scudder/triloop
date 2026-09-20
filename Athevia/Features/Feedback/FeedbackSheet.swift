import SwiftData
import SwiftUI

/// Post-workout capture. Every control has a sensible default so the athlete
/// can save without answering anything, which is what keeps this to ~10 seconds.
struct FeedbackSheet: View {
    let workout: PlannedWorkout

    @State private var draft = FeedbackDraft()
    @State private var failure: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.title)
                            .font(.subheadline.weight(.medium))
                        Text(workout.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year()))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    effortSection
                    painSection
                    recoverySection
                    symptomsSection
                    notesSection

                    Button(action: save) {
                        Text("Save Feedback")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
                .padding(20)
            }
            .navigationTitle("How did that workout feel?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Report not saved", isPresented: showingFailure) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    private var effortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            question("Effort (RPE)", detail: "How hard was it overall?")
            ScorePicker(
                range: RPEScale.minimum...RPEScale.maximum,
                selection: $draft.rpe,
                accessibilityPrefix: "Effort"
            )
            HStack {
                Text("Easy")
                Spacer()
                Text(RPEScale.label(for: draft.rpe))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Max effort")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func question(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var painSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            question("Pain", detail: "Did you have any pain?")
            ScorePicker(
                range: PainScale.minimum...PainScale.maximum,
                selection: $draft.painScore,
                accessibilityPrefix: "Pain"
            )
            Text(PainScale.label(for: draft.painScore))
                .font(.caption)
                .foregroundStyle(.secondary)

            if draft.reportsPain {
                Text("If yes, where?")
                    .font(.footnote)
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

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            question("Recovery", detail: "How do you feel right now?")

            HStack(spacing: 8) {
                ForEach(RecoveryFeeling.allCases) { feeling in
                    let selected = feeling == draft.recoveryFeeling

                    Button {
                        draft.recoveryFeeling = feeling
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: feeling.symbolName)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                                )
                                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            Text(feeling.displayName)
                                .font(.caption2)
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(feeling.displayName)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
    }

    private var symptomsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            question("Anything unusual?", detail: "Leave blank if nothing applies.")
            ChipGrid(
                values: WarningSymptom.allCases,
                title: \.displayName,
                isSelected: { draft.symptoms.contains($0) },
                toggle: { symptom in
                    if draft.symptoms.contains(symptom) {
                        draft.symptoms.remove(symptom)
                    } else {
                        draft.symptoms.insert(symptom)
                    }
                }
            )
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            question("Notes", detail: "Optional.")
            TextField(
                "Optional",
                text: $draft.notes,
                prompt: Text("Anything else to note?"),
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

        do {
            try modelContext.save()
            if let plan = workout.plan {
                try PlanStore(context: modelContext).generateNextWeekIfReady(after: plan)
            }
            dismiss()
        } catch {
            // A report that silently failed to save is worse than none: the
            // athlete believes the week is closed when it is not.
            failure = "Could not save your report: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
#Preview {
    FeedbackSheet(workout: PreviewData.workout(.running))
        .modelContainer(PreviewData.container)
}
#endif
