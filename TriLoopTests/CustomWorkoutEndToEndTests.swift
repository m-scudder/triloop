import Foundation
import SwiftData
import Testing
@testable import TriLoop

/// §10.3.19 and the phase's central claim: a workout the athlete built goes
/// through exactly the same machinery as one TriLoop prescribed.
///
/// Written as one path rather than separate assertions, because the risk this
/// guards against is a step quietly acquiring its own pipeline.
@MainActor
@Suite("Custom workout end to end")
struct CustomWorkoutEndToEndTests {

    private let calendar = Calendar.current

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: TriLoopSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func plan(in context: ModelContext, startingOn start: Date) -> WeeklyPlan {
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: start,
            endDate: calendar.date(byAdding: .day, value: 6, to: start) ?? start,
            parameters: TrainingParameters()
        )
        context.insert(plan)
        return plan
    }

    private func draft() -> WorkoutDraft {
        WorkoutDraft(
            sport: .running,
            name: "My Intervals",
            category: .intervals,
            purpose: "Short efforts with full recovery.",
            blocks: [
                WorkoutDraftBlock(kind: .warmUp, title: "Jog", durationSeconds: 600),
                WorkoutDraftBlock(
                    kind: .repeatBlock,
                    title: "Intervals",
                    repeatCount: 4,
                    children: [
                        WorkoutDraftBlock(kind: .work, title: "Hard", durationSeconds: 60, targetIntensity: .hard),
                        WorkoutDraftBlock(kind: .recovery, title: "Jog", durationSeconds: 120)
                    ]
                ),
                WorkoutDraftBlock(kind: .cooldown, title: "Jog", durationSeconds: 600)
            ],
            targetRPE: RPERange(7, 8)
        )
    }

    @Test("Build it, save it, plan it, train it, report it, analyse it")
    func fullJourney() throws {
        let context = ModelContext(try container())
        let today = calendar.startOfDay(for: .now)
        let week = plan(in: context, startingOn: today)

        // 1. Build and validate.
        let draft = draft()
        #expect(draft.isValid())
        let template = draft.template
        #expect(template.source == .athlete)

        // 2. Save to My Workouts.
        let stored = StoredWorkoutTemplate(template)
        context.insert(stored)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<StoredWorkoutTemplate>()).count == 1)

        // 3. It can be sent to Apple Watch before it is ever scheduled.
        #expect(WorkoutPlanBuilder.compatibility(for: template).isSupported)

        // 4. Add it to the plan.
        let workout = try WorkoutTemplateScheduler.add(template, to: week, on: today)
        try context.save()

        #expect(workout.origin == .custom)
        #expect(!workout.origin.isPrescribedByTriLoop)
        #expect(week.trainingSessions.contains { $0.id == workout.id })
        #expect(WorkoutStructure(steps: workout.steps) == template.structure)

        // 5. It reaches Today like any other session.
        let presentation = TodayPresentationBuilder.build(plan: week, date: today, calendar: calendar)
        #expect(presentation.state == .upcoming(workoutID: workout.id))

        // 6. Train it. The importer matches on sport and day, with no knowledge
        //    of where the workout came from.
        let activity = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: today.addingTimeInterval(9 * 3_600),
            endDate: today.addingTimeInterval(9 * 3_600 + 1_800),
            duration: 1_800,
            distanceMeters: 5_000
        )
        let result = WorkoutMatcher(calendar: calendar).match(
            planned: week.orderedWorkouts,
            with: [activity],
            asOf: today.addingTimeInterval(12 * 3_600)
        )
        let match = try #require(result.matches.first)
        #expect(match.planned.id == workout.id)

        let summary = ImportedWorkoutSummary(match.imported)
        context.insert(summary)
        workout.attach(summary)

        #expect(TodayPresentationBuilder.build(plan: week, date: today, calendar: calendar).state
                == .needsFeedback(workoutID: workout.id))

        // 7. Report it.
        workout.recordCompletion(with: FeedbackDraft(rpe: 7, painScore: 0, recoveryFeeling: .okay))
        try context.save()

        #expect(TodayPresentationBuilder.build(plan: week, date: today, calendar: calendar).state
                == .completed(workoutID: workout.id))

        // 8. It analyses through the shared Phase 9.1 path.
        let builder = TrainingIntelligenceBuilder(birthDate: nil, observedMaximumHeartRate: nil)
        let evidence = try #require(builder.evidence(from: workout, samples: []))
        let interpretation = WorkoutIntelligence.interpret(
            evidence,
            maximumHeartRate: nil,
            zoneSource: .ageBasedMaximum
        )

        #expect(interpretation.intensity.value != nil)
        #expect(interpretation.adherence == nil)
        #expect(interpretation.load.value != nil)

        // 9. Provenance survives everything that just happened.
        #expect(workout.origin == .custom)
    }

    @Test("Deleting the template afterwards leaves the training intact")
    func deletingTheTemplateKeepsHistory() throws {
        let container = try container()
        let context = ModelContext(container)
        let today = calendar.startOfDay(for: .now)
        let week = plan(in: context, startingOn: today)

        let stored = StoredWorkoutTemplate(draft().template)
        context.insert(stored)
        let workout = try WorkoutTemplateScheduler.add(stored.template, to: week, on: today)
        workout.recordCompletion(with: FeedbackDraft(rpe: 7, painScore: 0, recoveryFeeling: .okay))
        try context.save()

        context.delete(stored)
        try context.save()

        let reopened = ModelContext(container)
        #expect(try reopened.fetch(FetchDescriptor<StoredWorkoutTemplate>()).isEmpty)

        let survivor = try #require(try reopened.fetch(FetchDescriptor<PlannedWorkout>()).first)
        #expect(survivor.isCompleted)
        #expect(survivor.hasReport)
        #expect(survivor.steps.count == 3)
        #expect(survivor.origin == .custom)
    }

    @Test("A generated session on the same day keeps its own provenance")
    func provenanceIsPerSession() throws {
        let context = ModelContext(try container())
        let today = calendar.startOfDay(for: .now)
        let week = plan(in: context, startingOn: today)

        let generated = PrescribedSessions.session(.running, on: today, parameters: TrainingParameters())
        context.insert(generated)
        week.workouts.append(generated)

        let added = try WorkoutTemplateScheduler.add(draft().template, to: week, on: today)

        #expect(generated.origin == .generated)
        #expect(generated.origin.isPrescribedByTriLoop)
        #expect(added.origin == .custom)
        #expect(!added.origin.isPrescribedByTriLoop)
    }
}
