import Foundation
import SwiftData
import Testing

@testable import TriLoop

/// Proves an athlete who trained before personalisation existed keeps
/// everything, and can be brought through setup without losing history.
@Suite("Existing athlete migration")
@MainActor
struct AthleteMigrationTests {

    private func store() throws -> ModelContainer {
        try TriLoopModelContainer.make(inMemory: true)
    }

    /// A profile and a reported week, as a pre-Phase-8 build would have left them.
    private func seedHistory(in context: ModelContext) -> (AthleteProfile, WeeklyPlan) {
        let profile = AthleteProfile(name: "Athlete", trainingStartDate: .now)
        context.insert(profile)

        let plan = SeedWeekOne.makePlan(availability: .everything)
        context.insert(plan)

        if let run = plan.trainingSessions.first(where: { $0.discipline == .running }) {
            run.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 1, painLocations: [.calf]))
            run.recordRecoveryCheckIn(painScore: 1, soreness: .mild, energy: .normal)

            let summary = ImportedWorkoutSummary(
                healthKitUUID: UUID(),
                sport: .running,
                startDate: run.date,
                endDate: run.date.addingTimeInterval(1680),
                duration: 1680,
                distanceMeters: 3200,
                averageHeartRate: 142
            )
            context.insert(summary)
            run.attach(summary)
        }

        return (profile, plan)
    }

    @Test("A profile from before personalisation has no setup rather than a broken one")
    func migratedProfileHasNoSetup() throws {
        let container = try store()
        let context = container.mainContext
        let (profile, _) = seedHistory(in: context)
        try context.save()

        #expect(profile.setup == nil)
        #expect(profile.hasCompletedSetup == false)
    }

    @Test("History survives when the athlete completes setup afterwards")
    func historySurvivesUpgrade() throws {
        let container = try store()
        let context = container.mainContext
        let (profile, plan) = seedHistory(in: context)
        try context.save()

        let planCount = try context.fetchCount(FetchDescriptor<WeeklyPlan>())
        let workoutCount = try context.fetchCount(FetchDescriptor<PlannedWorkout>())

        profile.setup = AthleteSetup(
            goal: .firstTriathlon,
            baseline: AthleteBaseline(running: .runWalk, swimming: .continuous25, cycling: .twentyToThirty),
            schedule: .empty,
            stage: .complete,
            completedAt: .now
        )
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == planCount)
        #expect(try context.fetchCount(FetchDescriptor<PlannedWorkout>()) == workoutCount)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutFeedback>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<RecoveryCheckIn>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ImportedWorkoutSummary>()) == 1)
        #expect(plan.weekNumber == 1)
    }

    @Test("Setup survives a store reopen")
    func setupPersists() throws {
        let container = try store()
        let context = container.mainContext

        var schedule = AthleteSchedule.empty
        schedule.days = schedule.days.map { day in
            var updated = day
            if day.weekday == .tuesday { updated.sports = [.swimming] }
            if day.weekday == .saturday {
                updated.sports = [.running, .cycling]
                updated.maxDurationMinutes = 90
            }
            return updated
        }

        let profile = AthleteProfile(
            name: "Athlete",
            trainingStartDate: .now,
            poolLengthMeters: 50,
            setup: AthleteSetup(
                goal: .improveEndurance,
                baseline: AthleteBaseline(running: .continuous20To30Minutes, swimming: .continuous100, cycling: .sixtyPlus),
                schedule: schedule,
                stage: .complete,
                completedAt: .now
            )
        )
        context.insert(profile)
        try context.save()

        let reopened = ModelContext(container)
        let stored = try #require(try reopened.fetch(FetchDescriptor<AthleteProfile>()).first)
        let setup = try #require(stored.setup)

        #expect(stored.poolLengthMeters == 50)
        #expect(setup.goal == .improveEndurance)
        #expect(setup.baseline.running == .continuous20To30Minutes)
        #expect(setup.baseline.swimming == .continuous100)
        #expect(setup.baseline.cycling == .sixtyPlus)
        #expect(setup.schedule.allows(.swimming, on: .tuesday))
        #expect(setup.schedule.allows(.running, on: .monday) == false)
        #expect(setup.schedule.availability(on: .saturday).maxDurationMinutes == 90)
        #expect(stored.hasCompletedSetup)
    }

    @Test("An interrupted setup resumes where it stopped")
    func interruptedSetupResumes() throws {
        let container = try store()
        let context = container.mainContext

        let profile = AthleteProfile(
            name: "Athlete",
            trainingStartDate: .now,
            setup: AthleteSetup(goal: .generalFitness, stage: .swimming)
        )
        context.insert(profile)
        try context.save()

        let reopened = ModelContext(container)
        let stored = try #require(try reopened.fetch(FetchDescriptor<AthleteProfile>()).first)

        #expect(stored.setup?.stage == .swimming)
        #expect(stored.hasCompletedSetup == false)
        #expect(stored.setup?.goal == .generalFitness)
    }

    @Test("Setup stored by an earlier build decodes with defaults")
    func setupDecodesWithMissingKeys() throws {
        let stored = Data(#"{"goal":"firstTriathlon"}"#.utf8)

        let setup = try JSONDecoder().decode(AthleteSetup.self, from: stored)

        #expect(setup.goal == .firstTriathlon)
        #expect(setup.stage == .welcome)
        #expect(setup.completedAt == nil)
        #expect(setup.isComplete == false)
    }

    @Test("A plan generation reason survives a reopen")
    func generationReasonCodePersists() throws {
        let container = try store()
        let context = container.mainContext

        let plan = SeedWeekOne.makePlan(availability: .everything)
        plan.generationReasonCode = .initialAssessment
        context.insert(plan)
        try context.save()

        let reopened = ModelContext(container)
        let stored = try #require(try reopened.fetch(FetchDescriptor<WeeklyPlan>()).first)

        #expect(stored.generationReasonCode == .initialAssessment)
    }

    @Test("A plan from before reasons were coded reads as nil rather than trapping")
    func missingReasonCodeIsRepresentable() throws {
        let container = try store()
        let context = container.mainContext

        let plan = SeedWeekOne.makePlan(availability: .everything)
        context.insert(plan)
        try context.save()

        let reopened = ModelContext(container)
        let stored = try #require(try reopened.fetch(FetchDescriptor<WeeklyPlan>()).first)

        #expect(stored.generationReasonCode == nil)
        #expect(stored.generationReason.isEmpty == false)
    }

    @Test("A week's verdicts imply its reason, worst case first")
    func reasonFollowsTheWorstVerdict() {
        #expect(PlanGenerationReason.from([.progress, .progress]) == .weeklyProgression)
        #expect(PlanGenerationReason.from([.progress, .maintain]) == .weeklyProgression)
        #expect(PlanGenerationReason.from([.progress, .reduce]) == .weeklyReduction)
        #expect(PlanGenerationReason.from([.reduce, .recoveryRequired]) == .recovery)
        #expect(PlanGenerationReason.from([.maintain]) == .weeklyMaintain)
        #expect(PlanGenerationReason.from([]) == .weeklyMaintain)
    }
}
