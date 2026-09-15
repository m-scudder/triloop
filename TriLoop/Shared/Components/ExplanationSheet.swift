import SwiftUI

struct ExplanationSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("explanation.heading")
                content()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("explanation.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct InfoButton: View {
    private let concept: TrainingConceptExplanation?
    private let title: String
    private let definition: String
    private let usage: String?
    private let evidence: [DecisionExplanation.Evidence]
    private let detail: String?
    @State private var isPresented = false

    init(concept: TrainingConceptExplanation, evidence: [DecisionExplanation.Evidence] = [], detail: String? = nil) {
        self.concept = concept
        title = concept.title
        definition = concept.definition
        usage = concept.usage
        self.evidence = evidence
        self.detail = detail
    }

    init(title: String, explanation: String) {
        concept = nil
        self.title = title
        definition = explanation
        usage = nil
        evidence = []
        detail = nil
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More information about \(title.lowercased())")
        .accessibilityIdentifier("info.\(concept?.rawValue ?? title)")
        .sheet(isPresented: $isPresented) {
            ExplanationSheet(title: title) {
                Section("What it means") { Text(definition) }
                if let usage {
                    Section("How TriLoop uses it") { Text(usage) }
                }
                if !evidence.isEmpty || detail != nil {
                    Section("This session") {
                        ForEach(evidence) { item in
                            LabeledContent(item.label, value: item.value)
                        }
                        if let detail { Text(detail) }
                    }
                }
                if concept == .recovery {
                    Section(TrainingConceptExplanation.hrv.title) {
                        Text(TrainingConceptExplanation.hrv.definition)
                        Text(TrainingConceptExplanation.hrv.usage)
                    }
                    Section(TrainingConceptExplanation.restingHeartRate.title) {
                        Text(TrainingConceptExplanation.restingHeartRate.definition)
                    }
                }
            }
        }
    }
}

struct WhyButton: View {
    let explanation: DecisionExplanation
    @State private var isPresented = false

    var body: some View {
        Button("Why?") { isPresented = true }
            .frame(minHeight: 44)
            .buttonStyle(.borderless)
            .accessibilityLabel(explanation.accessibilityLabel)
            .accessibilityIdentifier("why.\(explanation.title)")
            .sheet(isPresented: $isPresented) {
                ExplanationSheet(title: explanation.title) {
                    if !explanation.evidence.isEmpty {
                        Section("Evidence") {
                            ForEach(explanation.evidence) { item in
                                LabeledContent(item.label, value: item.value)
                            }
                        }
                    }
                    if !explanation.reasons.isEmpty {
                        Section("Reasons") {
                            ForEach(Array(explanation.reasons.enumerated()), id: \.offset) { _, reason in
                                Text(reason)
                            }
                        }
                    }
                    if let change = explanation.change {
                        Section("Change") { Text(change) }
                    }
                }
            }
    }
}