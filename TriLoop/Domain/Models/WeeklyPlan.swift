import Foundation
import SwiftData

enum WeeklyPlanStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case active
    case completed
}

@Model
final class WeeklyPlan {
    var id: UUID
    var weekNumber: Int
    /// Start of day, Monday.
    var startDate: Date
    /// Start of day, Sunday.
    var endDate: Date
    var status: WeeklyPlanStatus
    var generatedAt: Date
    /// Human-readable explanation of why this week looks the way it does.
    /// Phase 4's generator writes here; Phase 7's LLM layer will read from here.
    var generationReason: String
    /// Machine-readable companion to `generationReason`, so a later explanation
    /// layer can reason about the cause instead of parsing the sentence.
    var generationReasonCode: PlanGenerationReason?
    /// The dials this week's sessions were built from. Carried forward and
    /// adjusted to produce the following week.
    var parameters: TrainingParameters = TrainingParameters()

    @Relationship(deleteRule: .cascade, inverse: \PlannedWorkout.plan)
    var workouts: [PlannedWorkout]

    init(
        id: UUID = UUID(),
        weekNumber: Int,
        startDate: Date,
        endDate: Date,
        status: WeeklyPlanStatus = .active,
        generatedAt: Date = .now,
        generationReason: String = "",
        generationReasonCode: PlanGenerationReason? = nil,
        parameters: TrainingParameters = TrainingParameters(),
        workouts: [PlannedWorkout] = []
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.generatedAt = generatedAt
        self.generationReason = generationReason
        self.generationReasonCode = generationReasonCode
        self.parameters = parameters
        self.workouts = workouts
    }

    var orderedWorkouts: [PlannedWorkout] {
        workouts.sorted { $0.date < $1.date }
    }

    var trainingSessions: [PlannedWorkout] {
        orderedWorkouts.filter { $0.discipline.isTrainingSession }
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= startDate && day <= endDate
    }

    func workout(on date: Date, calendar: Calendar = .current) -> PlannedWorkout? {
        orderedWorkouts.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Yesterday's reported session, when it has not been checked in on yet.
    /// Only the previous day is offered: a check-in three days later is guesswork.
    func sessionAwaitingCheckIn(on date: Date = .now, calendar: Calendar = .current) -> PlannedWorkout? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return orderedWorkouts.first {
            calendar.isDate($0.date, inSameDayAs: yesterday) && $0.awaitingRecoveryCheckIn
        }
    }
}
