import Foundation
import SwiftData
import Testing

@testable import TriLoop

@Suite("Workout feedback")
@MainActor
struct WorkoutFeedbackTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try TriLoopModelContainer.make(inMemory: true))
    }

    private func makeWorkout() -> PlannedWorkout {
        PlannedWorkout(
            date: Date(timeIntervalSince1970: 1_787_000_000),
            discipline: .running,
            title: "Running"
        )
    }

    @Test("Defaults describe an easy, painless session")
    func defaultDraftIsUnremarkable() {
        let draft = FeedbackDraft()

        #expect(draft.rpe == 3)
        #expect(draft.painScore == 0)
        #expect(draft.reportsPain == false)
        #expect(draft.recoveryFeeling == .good)
        #expect(draft.notes.isEmpty)
    }

    @Test("Pain locations are discarded when pain returns to zero")
    func painLocationsClearedWithoutPain() {
        let draft = FeedbackDraft(painScore: 0, painLocations: [.calf, .knee])

        #expect(draft.sanitized().painLocations.isEmpty)
        #expect(draft.makeFeedback().painLocations.isEmpty)
    }

    @Test("Pain locations survive when pain is reported")
    func painLocationsKeptWithPain() {
        let draft = FeedbackDraft(painScore: 4, painLocations: [.calf])
        let feedback = draft.makeFeedback()

        #expect(feedback.painScore == 4)
        #expect(feedback.painLocations == [.calf])
        #expect(feedback.reportedPain)
    }

    @Test("Whitespace-only notes are not persisted")
    func blankNotesAreTrimmed() {
        let draft = FeedbackDraft(notes: "   \n  ")

        #expect(draft.makeFeedback().notes.isEmpty)
    }

    @Test("Scores outside the scale are clamped")
    func scoresAreClamped() {
        let feedback = FeedbackDraft(rpe: 99, painScore: -4).makeFeedback()

        #expect(feedback.rpe == RPEScale.maximum)
        #expect(feedback.painScore == PainScale.minimum)
    }

    @Test("Recording completion stores the report and flips status")
    func recordingCompletionPersists() throws {
        let context = try makeContext()
        let workout = makeWorkout()
        context.insert(workout)

        let when = Date(timeIntervalSince1970: 1_787_040_000)
        workout.recordCompletion(
            with: FeedbackDraft(rpe: 4, recoveryFeeling: .fresh, notes: "Felt easy"),
            at: when
        )
        try context.save()

        #expect(workout.isCompleted)
        #expect(workout.completedAt == when)
        #expect(workout.feedback?.rpe == 4)
        #expect(workout.feedback?.recoveryFeeling == .fresh)
        #expect(workout.feedback?.notes == "Felt easy")
        #expect(workout.feedback?.workout?.id == workout.id)
    }

    @Test("Saved feedback survives a refetch")
    func feedbackRoundTripsThroughTheStore() throws {
        let context = try makeContext()
        let workout = makeWorkout()
        context.insert(workout)
        workout.recordCompletion(with: FeedbackDraft(rpe: 6, painScore: 2, painLocations: [.shin]))
        try context.save()

        let refetched = try context.fetch(FetchDescriptor<PlannedWorkout>())

        #expect(refetched.count == 1)
        #expect(refetched.first?.feedback?.rpe == 6)
        #expect(refetched.first?.feedback?.painLocations == [.shin])
    }

    @Test("Clearing a report returns the workout to planned")
    func clearingCompletionResetsState() throws {
        let context = try makeContext()
        let workout = makeWorkout()
        context.insert(workout)
        workout.recordCompletion(with: FeedbackDraft())
        try context.save()

        workout.clearCompletion()
        try context.save()

        #expect(workout.status == .planned)
        #expect(workout.feedback == nil)
        #expect(workout.completedAt == nil)

        let orphans = try context.fetch(FetchDescriptor<WorkoutFeedback>())
        #expect(orphans.isEmpty)
    }

    @Test("Re-recording replaces the report instead of stranding it")
    func rerecordingReplacesTheReport() throws {
        let context = try makeContext()
        let workout = makeWorkout()
        context.insert(workout)

        workout.recordCompletion(with: FeedbackDraft(rpe: 3))
        try context.save()
        workout.recordCompletion(with: FeedbackDraft(rpe: 8))
        try context.save()

        let stored = try context.fetch(FetchDescriptor<WorkoutFeedback>())
        #expect(stored.count == 1)
        #expect(workout.feedback?.rpe == 8)
    }

    @Test("Rest and recovery days do not accept feedback")
    func restDaysRejectFeedback() {
        let rest = PlannedWorkout(date: .now, discipline: .rest, title: "Rest")
        let recovery = PlannedWorkout(date: .now, discipline: .recovery, title: "Recovery")

        #expect(rest.acceptsFeedback == false)
        #expect(recovery.acceptsFeedback == false)
        #expect(makeWorkout().acceptsFeedback)
    }

    @Test("Recovery feeling severity is ordered")
    func recoverySeverityIsOrdered() {
        let ascending = RecoveryFeeling.allCases.sorted { $0.severity < $1.severity }

        #expect(ascending == [.fresh, .good, .okay, .tired, .exhausted])
    }
}
