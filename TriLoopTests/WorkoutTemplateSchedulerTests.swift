import Foundation
import SwiftData
import Testing
@testable import TriLoop

/// §10.2.8 and §10.2.9: adding a workout produces an ordinary planned session,
/// and never silently rewrites what the adaptive plan already decided.
@MainActor
@Suite("Adding a template to the plan")
struct WorkoutTemplateSchedulerTests {

    private let monday = Date(timeIntervalSince1970: 1_760_054_400)
    private let calendar = Calendar.current

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: TriLoopSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: monday)) ?? monday
    }

    private func plan(_ disciplines: [Discipline], in context: ModelContext) -> WeeklyPlan {
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: day(0),
            endDate: day(6),
            parameters: TrainingParameters()
        )
        context.insert(plan)

        for (offset, discipline) in disciplines.enumerated() {
            let workout = PlannedWorkout(
                date: day(offset),
                discipline: discipline,
                title: discipline.displayName,
                prescribedDurationSeconds: discipline.isTrainingSession ? 1_800 : nil
            )
            context.insert(workout)
            plan.workouts.append(workout)
        }
        return plan
    }

    private var builtIn: WorkoutTemplate {
        WorkoutLibrary.running[0]
    }

    private var mine: WorkoutTemplate {
        WorkoutTemplate(
            sport: .cycling,
            name: "My Ride",
            category: .easy,
            structure: WorkoutStructure([.work("Ride", seconds: 1_800)]),
            targetRPE: RPERange(3, 4)
        )
    }

    // MARK: - Instantiation

    @Test("A library workout becomes a normal planned session")
    func instantiation() {
        let workout = WorkoutTemplateScheduler.workout(from: builtIn, on: day(0), calendar: calendar)

        #expect(workout.discipline == .running)
        #expect(workout.title == builtIn.name)
        #expect(workout.goal == builtIn.purpose)
        #expect(workout.targetRPE == builtIn.targetRPE)
        #expect(workout.prescribedDurationSeconds == builtIn.totalDurationSeconds)
        #expect(WorkoutStructure(steps: workout.steps) == builtIn.structure)
    }

    @Test("Provenance follows who authored the template")
    func originFollowsSource() {
        #expect(WorkoutTemplateScheduler.workout(from: builtIn, on: day(0)).origin == .library)
        #expect(WorkoutTemplateScheduler.workout(from: mine, on: day(0)).origin == .custom)
    }

    @Test("Neither counts as training TriLoop prescribed")
    func addedWorkoutsAreNotPrescribed() {
        #expect(!WorkoutTemplateScheduler.workout(from: builtIn, on: day(0)).origin.isPrescribedByTriLoop)
        #expect(!WorkoutTemplateScheduler.workout(from: mine, on: day(0)).origin.isPrescribedByTriLoop)
    }

    // MARK: - Adding

    @Test("A day outside the week is refused")
    func outsideThePlan() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)

        #expect(throws: WorkoutTemplateScheduler.Failure.dateOutsidePlan) {
            try WorkoutTemplateScheduler.add(builtIn, to: week, on: day(9), calendar: calendar)
        }
    }

    @Test("An empty day simply takes the workout")
    func addToRestDay() throws {
        let context = ModelContext(try container())
        let week = plan([.rest, .rest], in: context)

        #expect(WorkoutTemplateScheduler.conflict(on: day(0), in: week, calendar: calendar) == .none)
        try WorkoutTemplateScheduler.add(builtIn, to: week, on: day(0), calendar: calendar)

        let onTheDay = week.orderedWorkouts.filter { calendar.isDate($0.date, inSameDayAs: day(0)) }
        // The rest placeholder gives way rather than sitting beside a session.
        #expect(onTheDay.count == 1)
        #expect(onTheDay.first?.origin == .library)
    }

    @Test("A generated session is never replaced without being asked")
    func addsAlongsideByDefault() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)
        let original = try #require(week.trainingSessions.first)

        try WorkoutTemplateScheduler.add(mine, to: week, on: day(0), calendar: calendar)

        let onTheDay = week.trainingSessions.filter { calendar.isDate($0.date, inSameDayAs: day(0)) }
        #expect(onTheDay.count == 2)
        #expect(onTheDay.contains { $0.id == original.id })
    }

    @Test("Replacing is possible, but only when asked for")
    func replaceOnRequest() throws {
        let container = try container()
        let context = ModelContext(container)
        let week = plan([.running], in: context)
        let original = try #require(week.trainingSessions.first)
        try context.save()

        try WorkoutTemplateScheduler.add(mine, to: week, on: day(0), resolving: .replace, calendar: calendar)
        // Saving is where an inconsistent relationship surfaces, so the test has
        // to go as far as the app does.
        try context.save()

        let onTheDay = week.trainingSessions.filter { calendar.isDate($0.date, inSameDayAs: day(0)) }
        #expect(onTheDay.count == 1)
        #expect(!onTheDay.contains { $0.id == original.id })

        let reopened = ModelContext(container)
        let stored = try reopened.fetch(FetchDescriptor<PlannedWorkout>())
        #expect(stored.count == 1)
        #expect(stored.first?.origin == .custom)
    }

    @Test("A session already trained cannot be replaced")
    func completedSessionsAreProtected() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)
        let original = try #require(week.trainingSessions.first)
        original.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 0, recoveryFeeling: .good))

        #expect(
            WorkoutTemplateScheduler.conflict(on: day(0), in: week, calendar: calendar)
                == .completedSession(workoutID: original.id, title: original.title)
        )
        #expect(throws: WorkoutTemplateScheduler.Failure.cannotReplaceCompletedSession) {
            try WorkoutTemplateScheduler.add(mine, to: week, on: day(0), resolving: .replace, calendar: calendar)
        }
    }

    @Test("A trained day still accepts a second session alongside")
    func alongsideACompletedSession() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)
        let original = try #require(week.trainingSessions.first)
        original.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 0, recoveryFeeling: .good))

        try WorkoutTemplateScheduler.add(mine, to: week, on: day(0), calendar: calendar)

        #expect(week.trainingSessions.count == 2)
        #expect(original.isCompleted)
    }

    @Test("The rest of the week is left alone")
    func restOfWeekUnchanged() throws {
        let context = ModelContext(try container())
        let week = plan([.running, .rest, .swimming, .rest, .cycling], in: context)
        let before = week.orderedWorkouts.filter { !calendar.isDate($0.date, inSameDayAs: day(3)) }.map(\.id)

        try WorkoutTemplateScheduler.add(mine, to: week, on: day(3), calendar: calendar)

        let after = week.orderedWorkouts.filter { !calendar.isDate($0.date, inSameDayAs: day(3)) }.map(\.id)
        #expect(Set(before) == Set(after))
    }
}
