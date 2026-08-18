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
    var completedAt: Date?

    var plan: WeeklyPlan?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutStep.workout)
    var steps: [WorkoutStep]

    @Relationship(deleteRule: .cascade, inverse: \WorkoutFeedback.workout)
    var feedback: WorkoutFeedback?

    @Relationship(deleteRule: .cascade, inverse: \ImportedWorkoutSummary.workout)
    var importedSummary: ImportedWorkoutSummary?

    @Relationship(deleteRule: .cascade, inverse: \RecoveryCheckIn.workout)
    var recoveryCheckIn: RecoveryCheckIn?

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

    var isCompleted: Bool { status == .completed }

    var isSkipped: Bool { status == .skipped }

    /// A training session whose day has passed with nothing recorded and no
    /// decision made. Derived rather than stored: it becomes true through the
    /// passage of time, so a stored flag would need sweeping to stay honest.
    func isMissed(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard discipline.isTrainingSession, status == .planned else { return false }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    /// Rest and recovery days are scheduled but never reported on.
    var acceptsFeedback: Bool { discipline.isTrainingSession }

    func recordCompletion(with draft: FeedbackDraft, at date: Date = .now) {
        discardFeedback()
        feedback = draft.makeFeedback(createdAt: date)
        status = .completed
        completedAt = date
    }

    /// A deliberate decision not to train, as opposed to a session that simply
    /// passed. The week can still close, but the work does not count as done.
    func skip() {
        discardFeedback()
        status = .skipped
        completedAt = nil
    }

    func clearCompletion() {
        discardFeedback()
        status = .planned
        completedAt = nil
    }

    /// Nulling a SwiftData relationship only unlinks the object; the cascade
    /// rule fires when the workout itself is deleted, not when the reference is
    /// cleared. Without an explicit delete the old report is stranded in the store.
    private func discardFeedback() {
        if let feedback {
            modelContext?.delete(feedback)
        }
        feedback = nil
    }

    /// Attaches an imported activity and marks the session done. Feedback is
    /// still required before the session can be assessed: §7 is explicit that
    /// sensor data alone is not enough.
    func attach(_ summary: ImportedWorkoutSummary) {
        if let importedSummary, importedSummary !== summary {
            modelContext?.delete(importedSummary)
        }
        importedSummary = summary
        if status == .planned {
            status = .completed
        }
        completedAt = completedAt ?? summary.endDate
    }

    /// How much of the prescription was actually covered. Falls back to 1 when
    /// nothing was imported, since a manually completed session has no evidence
    /// to contradict it.
    var recordedCompletion: Double {
        guard let importedSummary else { return 1 }
        return completionRatio(for: importedSummary.imported)
    }

    var awaitingFeedback: Bool {
        isCompleted && feedback == nil
    }

    /// Only a reported session can be checked in on: without knowing how it felt
    /// at the time, the next day tells us little.
    var awaitingRecoveryCheckIn: Bool {
        hasReport && recoveryCheckIn == nil
    }

    func recordRecoveryCheckIn(
        painScore: Int,
        soreness: SorenessLevel,
        energy: EnergyLevel,
        symptoms: [WarningSymptom] = [],
        at date: Date = .now
    ) {
        if let recoveryCheckIn {
            modelContext?.delete(recoveryCheckIn)
        }
        recoveryCheckIn = RecoveryCheckIn(
            date: date,
            painScore: painScore,
            soreness: soreness,
            energy: energy,
            symptoms: symptoms,
            createdAt: date
        )
    }
}
