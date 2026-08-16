import Foundation
import SwiftData

enum WorkoutStepKind: String, Codable, CaseIterable, Sendable {
    case warmUp
    case work
    case recovery
    case cooldown
    /// A container that repeats its `children` `repeatCount` times.
    case repeatBlock
}

enum TargetIntensity: String, Codable, CaseIterable, Sendable {
    case veryEasy
    case easy
    case steady
    case moderate
    case hard

    var displayName: String {
        switch self {
        case .veryEasy: "Very easy"
        case .easy: "Easy"
        case .steady: "Steady"
        case .moderate: "Moderate"
        case .hard: "Hard"
        }
    }
}

/// One prescribed piece of a workout.
///
/// Steps form a shallow tree: top-level steps belong to a `PlannedWorkout`, and
/// a `.repeatBlock` owns the child steps it cycles through. This lets interval
/// work ("6 × 1:00 run / 2:00 walk") be represented without a flattened list of
/// duplicated rows.
@Model
final class WorkoutStep {
    var id: UUID
    var order: Int
    var kind: WorkoutStepKind
    var title: String
    var instructions: String?
    var durationSeconds: TimeInterval?
    var distanceMeters: Double?
    var targetIntensity: TargetIntensity?
    /// Only meaningful for `.repeatBlock`.
    var repeatCount: Int?

    var workout: PlannedWorkout?
    var parent: WorkoutStep?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutStep.parent)
    var children: [WorkoutStep]

    init(
        id: UUID = UUID(),
        order: Int,
        kind: WorkoutStepKind,
        title: String,
        instructions: String? = nil,
        durationSeconds: TimeInterval? = nil,
        distanceMeters: Double? = nil,
        targetIntensity: TargetIntensity? = nil,
        repeatCount: Int? = nil,
        children: [WorkoutStep] = []
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.title = title
        self.instructions = instructions
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.targetIntensity = targetIntensity
        self.repeatCount = repeatCount
        self.children = children
    }

    var orderedChildren: [WorkoutStep] {
        children.sorted { $0.order < $1.order }
    }

    /// Total time this step contributes, expanding repeats. `nil` when the step
    /// is prescribed by distance only (common in swimming).
    var totalDurationSeconds: TimeInterval? {
        guard kind == .repeatBlock else { return durationSeconds }
        let childTotals = children.compactMap(\.totalDurationSeconds)
        guard !childTotals.isEmpty else { return nil }
        return childTotals.reduce(0, +) * Double(repeatCount ?? 1)
    }

    var totalDistanceMeters: Double? {
        guard kind == .repeatBlock else { return distanceMeters }
        let childTotals = children.compactMap(\.totalDistanceMeters)
        guard !childTotals.isEmpty else { return nil }
        return childTotals.reduce(0, +) * Double(repeatCount ?? 1)
    }
}

extension WorkoutStep {
    static func warmUp(
        order: Int,
        title: String,
        durationSeconds: TimeInterval? = nil,
        distanceMeters: Double? = nil,
        instructions: String? = nil
    ) -> WorkoutStep {
        WorkoutStep(
            order: order,
            kind: .warmUp,
            title: title,
            instructions: instructions,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            targetIntensity: .veryEasy
        )
    }

    static func cooldown(
        order: Int,
        title: String,
        durationSeconds: TimeInterval? = nil,
        distanceMeters: Double? = nil,
        instructions: String? = nil
    ) -> WorkoutStep {
        WorkoutStep(
            order: order,
            kind: .cooldown,
            title: title,
            instructions: instructions,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            targetIntensity: .veryEasy
        )
    }

    static func repeating(
        order: Int,
        title: String,
        count: Int,
        instructions: String? = nil,
        children: [WorkoutStep]
    ) -> WorkoutStep {
        WorkoutStep(
            order: order,
            kind: .repeatBlock,
            title: title,
            instructions: instructions,
            repeatCount: count,
            children: children
        )
    }
}
