import SwiftData
import SwiftUI

/// §8's next-day check. Three taps at most, and skippable: a check-in that feels
/// like an obligation stops being answered honestly.
struct RecoveryCheckInSheet: View {
    let workout: PlannedWorkout

    @State private var painScore = 0
    @State private var soreness: SorenessLevel = .none
    @State private var energy: EnergyLevel = .normal
    @State private var symptoms: Set<WarningSymptom> = []
    @State private var failure: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("How do you feel after \(workout.title)?")
                        .font(.title3.weight(.medium))

                    LabeledSection(title: "Pain") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(PainScale.label(for: painScore))
                                .font(.title3.weight(.medium))
                            ScorePicker(
                                range: PainScale.minimum...PainScale.maximum,
                                selection: $painScore,
                                accessibilityPrefix: "Pain"
                            )
                        }
                    }

                    LabeledSection(title: "Soreness") {
                        ChipGrid(
                            values: SorenessLevel.allCases,
                            title: \.displayName,
                            isSelected: { $0 == soreness },
                            toggle: { soreness = $0 }
                        )
                    }

                    LabeledSection(title: "Energy") {
                        ChipGrid(
                            values: EnergyLevel.allCases,
                            title: \.displayName,
                            isSelected: { $0 == energy },
                            toggle: { energy = $0 }
                        )
                    }

                    LabeledSection(title: "Anything unusual?") {
                        ChipGrid(
                            values: WarningSymptom.allCases,
                            title: \.displayName,
                            isSelected: { symptoms.contains($0) },
                            toggle: { symptom in
                                if symptoms.contains(symptom) {
                                    symptoms.remove(symptom)
                                } else {
                                    symptoms.insert(symptom)
                                }
                            }
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("Yesterday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
            .alert("Check-in not saved", isPresented: showingFailure) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func save() {
        workout.recordRecoveryCheckIn(
            painScore: painScore,
            soreness: soreness,
            energy: energy,
            symptoms: symptoms.sorted { $0.rawValue < $1.rawValue }
        )

        do {
            try modelContext.save()
            dismiss()
        } catch {
            failure = "Could not save your check-in: \(error.localizedDescription)"
        }
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}
