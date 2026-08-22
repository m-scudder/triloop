import SwiftData
import SwiftUI

/// Build a workout from TriLoop's own primitives.
///
/// §10.3: the athlete works with the same blocks the engine uses, so what they
/// create is executable, sendable and analysable exactly like anything else.
struct WorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [AthleteProfile]
    @Query private var stored: [StoredWorkoutTemplate]

    @State private var draft: WorkoutDraft
    /// Sport decides which measures make sense, so it is fixed once blocks exist.
    private let isNew: Bool

    init(draft: WorkoutDraft, isNew: Bool = true) {
        _draft = State(initialValue: draft)
        self.isNew = isNew
    }

    private var poolLength: Double? {
        draft.sport == .swimming ? profiles.first?.poolLengthMeters : nil
    }

    private var issues: [WorkoutTemplateIssue] {
        draft.issues(poolLengthMeters: poolLength)
    }

    var body: some View {
        Form {
            detailsSection
            effortSection
            blocksSection
            if !issues.isEmpty { issuesSection }
            if draft.isValid(poolLengthMeters: poolLength) { previewSection }
        }
        .navigationTitle(isNew ? "New Workout" : "Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!draft.isValid(poolLengthMeters: poolLength))
            }
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section {
            TextField("Name", text: $draft.name)

            if draft.blocks.isEmpty {
                Picker("Sport", selection: $draft.sport) {
                    ForEach(Sport.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } else {
                LabeledContent("Sport", value: draft.sport.displayName)
            }

            Picker("Type", selection: $draft.category) {
                ForEach(WorkoutCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }

            TextField("What is it for? (optional)", text: $draft.purpose, axis: .vertical)
        } header: {
            Text("Workout")
        } footer: {
            if !draft.blocks.isEmpty {
                Text("Sport is fixed once the workout has blocks, because it decides what they can be measured in.")
            }
        }
    }

    private var effortSection: some View {
        Section {
            Picker("Target effort", selection: effortBinding) {
                ForEach(EffortPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
        } header: {
            Text("Effort")
        } footer: {
            Text("How hard the session should feel overall, on the same 1–10 scale you report with.")
        }
    }

    private var blocksSection: some View {
        Section {
            ForEach($draft.blocks) { $block in
                NavigationLink {
                    WorkoutBlockEditor(block: $block, sport: draft.sport)
                } label: {
                    BlockRow(block: block)
                }
            }
            .onDelete { draft.blocks.remove(atOffsets: $0) }
            .onMove { draft.blocks.move(fromOffsets: $0, toOffset: $1) }

            Menu("Add a block") {
                Button("Warm-up") { add(.warmUp) }
                Button("Work") { add(.work) }
                Button("Recovery") { add(.recovery) }
                Button("Repeat set") { add(.repeatBlock) }
                Button("Cool-down") { add(.cooldown) }
            }
        } header: {
            Text("Structure")
        } footer: {
            Text("Swipe to remove a block, or drag to reorder.")
        }
    }

    private var issuesSection: some View {
        Section {
            ForEach(issues.map(\.message), id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Before you can save")
        }
    }

    /// §10.3.12: previewed through the same renderer Workout Detail uses.
    private var previewSection: some View {
        Section {
            WorkoutPrescriptionView(
                workout: WorkoutTemplateScheduler.workout(from: draft.template, on: .now)
            )
            .padding(.vertical, 8)
        } header: {
            Text("Preview")
        }
    }

    // MARK: - Actions

    private var effortBinding: Binding<EffortPreset> {
        Binding(
            get: { EffortPreset(draft.targetRPE) },
            set: { draft.targetRPE = $0.range }
        )
    }

    private func add(_ kind: WorkoutStepKind) {
        draft.blocks.append(draft.newBlock(kind))
    }

    private func save() {
        let template = draft.template

        if let existing = stored.first(where: { $0.id == template.id }) {
            existing.apply(template)
        } else {
            modelContext.insert(StoredWorkoutTemplate(template))
        }
        try? modelContext.save()
        dismiss()
    }
}

/// The five efforts an athlete can actually distinguish, on the RPE scale they
/// already report with.
enum EffortPreset: String, CaseIterable, Hashable {
    case veryEasy
    case easy
    case steady
    case hard
    case veryHard

    init(_ range: RPERange?) {
        switch range?.upper ?? 4 {
        case ...3: self = .veryEasy
        case 4: self = .easy
        case 5...6: self = .steady
        case 7...8: self = .hard
        default: self = .veryHard
        }
    }

    var range: RPERange {
        switch self {
        case .veryEasy: RPERange(2, 3)
        case .easy: RPERange(3, 4)
        case .steady: RPERange(5, 6)
        case .hard: RPERange(7, 8)
        case .veryHard: RPERange(9, 10)
        }
    }

    var displayName: String {
        switch self {
        case .veryEasy: "Very easy · 2–3"
        case .easy: "Easy · 3–4"
        case .steady: "Steady · 5–6"
        case .hard: "Hard · 7–8"
        case .veryHard: "Very hard · 9–10"
        }
    }
}

private struct BlockRow: View {
    let block: WorkoutDraftBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(block.title.isEmpty ? "Untitled" : block.title)
                .font(.body)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        if block.kind == .repeatBlock {
            let count = block.repeatCount ?? 1
            return "\(count) × \(block.children.count) block\(block.children.count == 1 ? "" : "s")"
        }
        var parts = [kindName]
        if let seconds = block.durationSeconds {
            parts.append(TrainingFormatter.totalDuration(seconds: seconds))
        }
        if let meters = block.distanceMeters {
            parts.append(TrainingFormatter.distance(meters: meters))
        }
        return parts.joined(separator: " · ")
    }

    private var kindName: String {
        switch block.kind {
        case .warmUp: "Warm-up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        case .repeatBlock: "Repeat"
        }
    }
}

/// Editing one block, showing only what the sport can actually be measured in.
struct WorkoutBlockEditor: View {
    @Binding var block: WorkoutDraftBlock
    let sport: Sport

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $block.title)
            }

            if block.kind == .repeatBlock {
                repeatSection
            } else {
                measureSection
                intensitySection
            }
        }
        .navigationTitle(block.title.isEmpty ? "Block" : block.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var repeatSection: some View {
        Section {
            Stepper(
                "Repeat \(block.repeatCount ?? 2) times",
                value: Binding(get: { block.repeatCount ?? 2 }, set: { block.repeatCount = $0 }),
                in: 2...20
            )

            ForEach($block.children) { $child in
                NavigationLink {
                    WorkoutBlockEditor(block: $child, sport: sport)
                } label: {
                    BlockRow(block: child)
                }
            }
            .onDelete { block.children.remove(atOffsets: $0) }
        } header: {
            Text("Set")
        } footer: {
            Text("A set needs at least one block inside it.")
        }
    }

    @ViewBuilder
    private var measureSection: some View {
        Section {
            // Rest is counted in seconds even in the pool.
            if usesDistance {
                Stepper(
                    TrainingFormatter.distance(meters: block.distanceMeters ?? 0),
                    value: Binding(get: { block.distanceMeters ?? 0 }, set: { block.distanceMeters = $0 }),
                    in: distanceRange,
                    step: distanceStep
                )
            } else {
                Stepper(
                    TrainingFormatter.totalDuration(seconds: block.durationSeconds ?? 0),
                    value: Binding(get: { block.durationSeconds ?? 0 }, set: { block.durationSeconds = $0 }),
                    in: 30...7_200,
                    step: 30
                )
            }
        } header: {
            Text(usesDistance ? "Distance" : "Duration")
        }
    }

    private var intensitySection: some View {
        Section {
            Picker("Intensity", selection: intensityBinding) {
                Text("Not set").tag(TargetIntensity?.none)
                ForEach(TargetIntensity.allCases, id: \.self) { intensity in
                    Text(intensity.displayName).tag(TargetIntensity?.some(intensity))
                }
            }
        } header: {
            Text("How it should feel")
        }
    }

    private var intensityBinding: Binding<TargetIntensity?> {
        Binding(get: { block.targetIntensity }, set: { block.targetIntensity = $0 })
    }

    private var usesDistance: Bool {
        sport == .swimming && block.kind != .recovery
    }

    private var distanceStep: Double { sport == .swimming ? 25 : 100 }
    private var distanceRange: ClosedRange<Double> { distanceStep...10_000 }
}
