import Foundation

/// One piece of a workout, independent of persistence.
///
/// A value mirror of `WorkoutStep`, which is a `@Model` owned by a
/// `PlannedWorkout` through a cascading relationship and so cannot describe a
/// workout that has not been scheduled. Templates need exactly that: a shape
/// with no occurrence attached.
///
/// Order is positional rather than stored, so a structure cannot be built with
/// two blocks claiming the same index.
struct WorkoutBlock: Codable, Equatable, Sendable {
    var kind: WorkoutStepKind
    var title: String
    var instructions: String?
    var durationSeconds: TimeInterval?
    var distanceMeters: Double?
    var targetIntensity: TargetIntensity?
    /// Only meaningful for `.repeatBlock`.
    var repeatCount: Int?
    var children: [WorkoutBlock]

    init(
        kind: WorkoutStepKind,
        title: String,
        instructions: String? = nil,
        durationSeconds: TimeInterval? = nil,
        distanceMeters: Double? = nil,
        targetIntensity: TargetIntensity? = nil,
        repeatCount: Int? = nil,
        children: [WorkoutBlock] = []
    ) {
        self.kind = kind
        self.title = title
        self.instructions = instructions
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.targetIntensity = targetIntensity
        self.repeatCount = repeatCount
        self.children = children
    }

    /// Time this block contributes, expanding repeats. Mirrors
    /// `WorkoutStep.totalDurationSeconds` so a template and the workout it
    /// produces can never disagree about length.
    var totalDurationSeconds: TimeInterval? {
        guard kind == .repeatBlock else { return durationSeconds }
        let totals = children.compactMap(\.totalDurationSeconds)
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) * Double(repeatCount ?? 1)
    }

    var totalDistanceMeters: Double? {
        guard kind == .repeatBlock else { return distanceMeters }
        let totals = children.compactMap(\.totalDistanceMeters)
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) * Double(repeatCount ?? 1)
    }
}

/// The shape of a session, shared by templates and scheduled workouts.
struct WorkoutStructure: Codable, Equatable, Sendable {
    var blocks: [WorkoutBlock]

    init(_ blocks: [WorkoutBlock] = []) {
        self.blocks = blocks
    }

    var isEmpty: Bool { blocks.isEmpty }

    /// A structure with something the athlete actually does in it.
    var hasExecutableBlock: Bool {
        blocks.contains { $0.kind != .warmUp && $0.kind != .cooldown }
    }

    var totalDurationSeconds: TimeInterval? {
        let totals = blocks.compactMap(\.totalDurationSeconds)
        return totals.isEmpty ? nil : totals.reduce(0, +)
    }

    var totalDistanceMeters: Double? {
        let totals = blocks.compactMap(\.totalDistanceMeters)
        return totals.isEmpty ? nil : totals.reduce(0, +)
    }
}

// MARK: - Persistence boundary

extension WorkoutStructure {
    /// Reads the shape out of a scheduled workout, so a built session can seed
    /// a template without the template holding persisted objects.
    init(steps: [WorkoutStep]) {
        self.init(steps.sorted { $0.order < $1.order }.map(WorkoutBlock.init(step:)))
    }

    /// Materialises the rows a `PlannedWorkout` owns.
    ///
    /// Fresh identifiers every time: two workouts instantiated from one
    /// template are separate occurrences, and editing the template later must
    /// not reach back into either (§10.3.15).
    func makeSteps() -> [WorkoutStep] {
        blocks.enumerated().map { index, block in block.makeStep(order: index) }
    }
}

extension WorkoutBlock {
    init(step: WorkoutStep) {
        self.init(
            kind: step.kind,
            title: step.title,
            instructions: step.instructions,
            durationSeconds: step.durationSeconds,
            distanceMeters: step.distanceMeters,
            targetIntensity: step.targetIntensity,
            repeatCount: step.repeatCount,
            children: step.orderedChildren.map(WorkoutBlock.init(step:))
        )
    }

    func makeStep(order: Int) -> WorkoutStep {
        WorkoutStep(
            order: order,
            kind: kind,
            title: title,
            instructions: instructions,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            targetIntensity: targetIntensity,
            repeatCount: repeatCount,
            children: children.enumerated().map { index, child in child.makeStep(order: index) }
        )
    }
}
