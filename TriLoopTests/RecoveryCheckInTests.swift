import Foundation
import SwiftData
import Testing

@testable import TriLoop

@Suite("Next-day recovery")
struct RecoveryCheckInTests {
    private let engine = TrainingEngine()

    private func goodSession() -> (WorkoutResult, FeedbackSummary) {
        (
            WorkoutResult(sport: .running, completion: 1.0),
            FeedbackSummary(rpe: 3, painScore: 0, recoveryFeeling: .good)
        )
    }

    @Test("Without a check-in the session is judged on its own merits")
    func missingCheckInDoesNotBlock() {
        let (result, feedback) = goodSession()

        #expect(engine.evaluate(result: result, feedback: feedback, recovery: nil).status == .progress)
    }

    @Test("A clean next day still progresses")
    func cleanNextDayProgresses() {
        let (result, feedback) = goodSession()
        let recovery = RecoverySummary(painScore: 0, soreness: .none, energy: .good)

        let assessment = engine.evaluate(result: result, feedback: feedback, recovery: recovery)

        #expect(assessment.status == .progress)
        #expect(assessment.reasons.contains(.recoveredOvernight))
    }

    @Test("Lingering soreness holds the workload")
    func sorenessBlocksProgression() {
        let (result, feedback) = goodSession()
        let recovery = RecoverySummary(soreness: .moderate)

        let assessment = engine.evaluate(result: result, feedback: feedback, recovery: recovery)

        #expect(assessment.status == .maintain)
        #expect(assessment.reasons.contains(.lingeringSoreness(.moderate)))
    }

    @Test("Low energy the next day holds the workload")
    func lowEnergyBlocksProgression() {
        let (result, feedback) = goodSession()
        let assessment = engine.evaluate(
            result: result, feedback: feedback, recovery: RecoverySummary(energy: .low)
        )

        #expect(assessment.status == .maintain)
        #expect(assessment.reasons.contains(.lowEnergyNextDay(.low)))
    }

    @Test("Next-day pain reduces running even after an easy session")
    func nextDayPainReducesRunning() {
        let (result, feedback) = goodSession()
        let assessment = engine.evaluate(
            result: result, feedback: feedback, recovery: RecoverySummary(painScore: 4)
        )

        #expect(assessment.status == .reduce)
        #expect(assessment.reasons.contains(.nextDayPain(score: 4)))
    }

    @Test("Severe next-day pain requires recovery")
    func severeNextDayPainStopsTraining() {
        let (result, feedback) = goodSession()
        let assessment = engine.evaluate(
            result: result, feedback: feedback, recovery: RecoverySummary(painScore: 8)
        )

        #expect(assessment.status == .recoveryRequired)
        #expect(assessment.adjustment == .substituteRecovery)
    }

    @Test("A symptom reported the next day overrides a flawless session")
    func nextDaySymptomOverrides() {
        let (result, feedback) = goodSession()
        let assessment = engine.evaluate(
            result: result,
            feedback: feedback,
            recovery: RecoverySummary(symptoms: [.numbness])
        )

        #expect(assessment.status == .recoveryRequired)
        #expect(assessment.reasons.contains(.warningSymptom(.numbness)))
    }

    @Test("A symptom reported during the session overrides it too")
    func sessionSymptomOverrides() {
        let assessment = engine.evaluate(
            result: WorkoutResult(sport: .cycling, completion: 1.0),
            feedback: FeedbackSummary(rpe: 2, symptoms: [.chestDiscomfort])
        )

        #expect(assessment.status == .recoveryRequired)
    }
}

@Suite("Recovery check-in storage")
@MainActor
struct RecoveryCheckInStorageTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func monday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        return calendar.date(from: components) ?? .now
    }

    @Test("A check-in round-trips and feeds the analysis")
    func checkInPersists() throws {
        let context = ModelContext(try TriLoopModelContainer.make(inMemory: true))
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        context.insert(plan)

        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        run.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        run.recordRecoveryCheckIn(painScore: 0, soreness: .moderate, energy: .normal)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<RecoveryCheckIn>())
        #expect(stored.count == 1)
        #expect(run.recoveryCheckIn?.soreness == .moderate)

        // Soreness must stop the week progressing, not just be recorded.
        let running = WeeklyAnalyser().analyse(plan).analysis(for: .running)
        #expect(running?.status == .maintain)
    }

    @Test("Re-answering replaces the check-in rather than stranding it")
    func checkInIsReplaced() throws {
        let context = ModelContext(try TriLoopModelContainer.make(inMemory: true))
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        context.insert(plan)

        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        run.recordCompletion(with: FeedbackDraft(rpe: 3))
        run.recordRecoveryCheckIn(painScore: 0, soreness: .none, energy: .good)
        try context.save()
        run.recordRecoveryCheckIn(painScore: 3, soreness: .significant, energy: .low)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<RecoveryCheckIn>()).count == 1)
        #expect(run.recoveryCheckIn?.painScore == 3)
    }

    @Test("Only yesterday's reported session is offered for check-in")
    func onlyYesterdayIsOffered() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let monday = try #require(plan.workout(on: monday(), calendar: calendar))
        monday.recordCompletion(with: FeedbackDraft(rpe: 3))

        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday.date) ?? monday.date
        #expect(plan.sessionAwaitingCheckIn(on: tuesday, calendar: calendar)?.id == monday.id)

        // Two days later the moment has passed.
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday.date) ?? monday.date
        #expect(plan.sessionAwaitingCheckIn(on: wednesday, calendar: calendar) == nil)
    }

    @Test("An unreported session is not offered a check-in")
    func unreportedSessionIsNotOffered() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let monday = try #require(plan.workout(on: monday(), calendar: calendar))
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday.date) ?? monday.date

        #expect(plan.sessionAwaitingCheckIn(on: tuesday, calendar: calendar) == nil)
    }
}
