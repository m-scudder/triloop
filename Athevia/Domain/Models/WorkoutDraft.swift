import Foundation

/// One block while it is being edited.
///
/// `WorkoutBlock` is deliberately not `Identifiable`: its order comes from its
/// position, which is right for a finished structure but useless to a list the
/// athlete can reorder and delete from. The draft adds identity for exactly as
/// long as the editor needs it.
struct WorkoutDraftBlock: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: WorkoutStepKind
    var title: String
    var durationSeconds: TimeInterval?
    var distanceMeters: Double?
    var targetIntensity: TargetIntensity?
    var repeatCount: Int?
    var children: [WorkoutDraftBlock]

    init(
        id: UUID = UUID(),
        kind: WorkoutStepKind,
        title: String,
        durationSeconds: TimeInterval? = nil,
        distanceMeters: Double? = nil,
        targetIntensity: TargetIntensity? = nil,
        repeatCount: Int? = nil,
        children: [WorkoutDraftBlock] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.targetIntensity = targetIntensity
        self.repeatCount = repeatCount
        self.children = children
    }

    init(_ block: WorkoutBlock) {
        self.init(
            kind: block.kind,
            title: block.title,
            durationSeconds: block.durationSeconds,
            distanceMeters: block.distanceMeters,
            targetIntensity: block.targetIntensity,
            repeatCount: block.repeatCount,
            children: block.children.map(WorkoutDraftBlock.init)
        )
    }

    var block: WorkoutBlock {
        WorkoutBlock(
            kind: kind,
            title: title,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            targetIntensity: targetIntensity,
            repeatCount: repeatCount,
            children: children.map(\.block)
        )
    }
}

/// A workout while the athlete is building it.
///
/// §10.10: transient. Nothing here is persisted — the draft becomes a
/// `WorkoutTemplate` only once it validates, and only that is saved.
struct WorkoutDraft: Equatable, Sendable {
    /// Kept across edits so saving twice updates one template rather than
    /// creating a second.
    let id: UUID
    var sport: Sport
    var name: String
    var category: WorkoutCategory
    var purpose: String
    var blocks: [WorkoutDraftBlock]
    var targetRPE: RPERange?

    init(
        id: UUID = UUID(),
        sport: Sport,
        name: String = "",
        category: WorkoutCategory = .easy,
        purpose: String = "",
        blocks: [WorkoutDraftBlock] = [],
        targetRPE: RPERange? = RPERange(3, 4)
    ) {
        self.id = id
        self.sport = sport
        self.name = name
        self.category = category
        self.purpose = purpose
        self.blocks = blocks
        self.targetRPE = targetRPE
    }

    /// Editing an athlete's own workout: same identity, so saving replaces it.
    init(editing template: WorkoutTemplate) {
        self.init(
            id: template.id,
            sport: template.sport,
            name: template.name,
            category: template.category,
            purpose: template.purpose,
            blocks: template.structure.blocks.map(WorkoutDraftBlock.init),
            targetRPE: template.targetRPE
        )
    }

    /// §10.3.14: customising a built-in clones it. A new identity, because the
    /// original must stay exactly as it shipped.
    init(customising template: WorkoutTemplate) {
        self.init(
            id: UUID(),
            sport: template.sport,
            name: "\(template.name) — Custom",
            category: template.category,
            purpose: template.purpose,
            blocks: template.structure.blocks.map(WorkoutDraftBlock.init),
            targetRPE: template.targetRPE
        )
    }

    /// Always athlete-owned: a draft is something the athlete made.
    var template: WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            sport: sport,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
            structure: WorkoutStructure(blocks.map(\.block)),
            targetRPE: targetRPE,
            source: .athlete
        )
    }

    func issues(poolLengthMeters: Double? = nil) -> [WorkoutTemplateIssue] {
        WorkoutTemplateValidator.issues(in: template, poolLengthMeters: poolLengthMeters)
    }

    func isValid(poolLengthMeters: Double? = nil) -> Bool {
        issues(poolLengthMeters: poolLengthMeters).isEmpty
    }

    /// What a new block should look like for this sport.
    ///
    /// Swimmers think in distance and everyone else in time, so the editor opens
    /// on the measure the athlete would actually type.
    func newBlock(_ kind: WorkoutStepKind) -> WorkoutDraftBlock {
        switch kind {
        case .repeatBlock:
            WorkoutDraftBlock(
                kind: .repeatBlock,
                title: "Main set",
                repeatCount: 4,
                children: [newBlock(.work), newBlock(.recovery)]
            )
        case .warmUp:
            measured(kind: .warmUp, title: "Warm-up", intensity: .veryEasy)
        case .cooldown:
            measured(kind: .cooldown, title: "Cool-down", intensity: .veryEasy)
        case .recovery:
            // Rest is counted in seconds even in the pool.
            WorkoutDraftBlock(kind: .recovery, title: "Recovery", durationSeconds: 60)
        case .work:
            measured(kind: .work, title: "Work", intensity: .easy)
        }
    }

    private func measured(
        kind: WorkoutStepKind,
        title: String,
        intensity: TargetIntensity
    ) -> WorkoutDraftBlock {
        sport == .swimming
            ? WorkoutDraftBlock(kind: kind, title: title, distanceMeters: 100, targetIntensity: intensity)
            : WorkoutDraftBlock(kind: kind, title: title, durationSeconds: 600, targetIntensity: intensity)
    }
}
