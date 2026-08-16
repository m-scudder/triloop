import Foundation
import SwiftData

enum PlannedWorkoutStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case completed
    case skipped
}

@Model
final class PlannedWorkout {
    var id: UUID
    /// Start of day for the scheduled date. Time of day is not prescribed.
    var date: Date
    var discipline: Discipline
    var title: String
    var goal: String
    var targetRPE: RPERange?
    /// Author-specified total. When nil, the total is derived from `steps`.
    var prescribedDurationSeconds: TimeInterval?
    var targetDistanceMeters: Double?
    var status: PlannedWorkoutStatus

    var plan: WeeklyPlan?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutStep.workout)
    var steps: [WorkoutStep]

    init(
        id: UUID = UUID(),
        date: Date,
        discipline: Discipline,
        title: String,
        goal: String = "",
        targetRPE: RPERange? = nil,
        prescribedDurationSeconds: TimeInterval? = nil,
        targetDistanceMeters: Double? = nil,
        status: PlannedWorkoutStatus = .planned,
        steps: [WorkoutStep] = []
    ) {
        self.id = id
        self.date = date
        self.discipline = discipline
        self.title = title
        self.goal = goal
        self.targetRPE = targetRPE
        self.prescribedDurationSeconds = prescribedDurationSeconds
        self.targetDistanceMeters = targetDistanceMeters
        self.status = status
        self.steps = steps
    }

    var orderedSteps: [WorkoutStep] {
        steps.sorted { $0.order < $1.order }
    }

    var estimatedDurationSeconds: TimeInterval? {
        if let prescribedDurationSeconds { return prescribedDurationSeconds }
        let totals = steps.compactMap(\.totalDurationSeconds)
        return totals.isEmpty ? nil : totals.reduce(0, +)
    }

    var estimatedDistanceMeters: Double? {
        if let targetDistanceMeters { return targetDistanceMeters }
        let totals = steps.compactMap(\.totalDistanceMeters)
        return totals.isEmpty ? nil : totals.reduce(0, +)
    }
}
