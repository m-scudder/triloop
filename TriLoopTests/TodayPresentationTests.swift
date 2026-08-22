import Foundation
import SwiftData
import Testing
@testable import TriLoop

/// §27: the priority must be deterministic, not an accident of view ordering.
@MainActor
@Suite("Today presentation")
struct TodayPresentationTests {

    private let monday = Date(timeIntervalSince1970: 1_760_054_400)
    private let calendar = Calendar.current

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: TriLoopSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A week whose days are described by discipline, starting on `monday`.
    private func plan(
        _ disciplines: [Discipline],
        in context: ModelContext
    ) -> WeeklyPlan {
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: calendar.date(byAdding: .day, value: 6, to: monday) ?? monday,
            parameters: TrainingParameters()
        )
        context.insert(plan)

        for (offset, discipline) in disciplines.enumerated() {
            let workout = PlannedWorkout(
                date: calendar.date(byAdding: .day, value: offset, to: monday) ?? monday,
                discipline: discipline,
                title: discipline.displayName,
                targetRPE: discipline.isTrainingSession ? RPERange(3, 4) : nil,
                prescribedDurationSeconds: discipline.isTrainingSession ? 1_800 : nil
            )
            context.insert(workout)
            plan.workouts.append(workout)
        }

        return plan
    }

    private func build(_ plan: WeeklyPlan?, dayOffset: Int = 0, finishedOnWatch: Set<UUID> = []) -> TodayPresentation {
        TodayPresentationBuilder.build(
            plan: plan,
            finishedOnWatch: finishedOnWatch,
            date: calendar.date(byAdding: .day, value: dayOffset, to: monday) ?? monday,
            calendar: calendar
        )
    }

    // MARK: - Priority

    @Test("Recovery outranks everything else")
    func recoveryWins() throws {
        let context = ModelContext(try container())
        let week = plan([.recovery, .running], in: context)

        // Even with a completed session awaiting feedback, recovery leads.
        let recovery = try #require(week.orderedWorkouts.first)
        #expect(build(week).state == .recoveryRequired(workoutID: recovery.id))
    }

    @Test("Feedback outranks a session still to come")
    func feedbackBeatsUpcoming() throws {
        let context = ModelContext(try container())
        let week = plan([.running, .swimming], in: context)

        let run = try #require(week.orderedWorkouts.first)
        run.status = .completed

        // §27's named example: completed with feedback missing must not be
        // displaced by tomorrow's session.
        #expect(build(week).state == .needsFeedback(workoutID: run.id))
    }

    @Test("An outstanding session outranks one already finished")
    func outstandingBeatsCompleted() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)

        let run = try #require(week.orderedWorkouts.first)
        run.status = .completed
        run.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))

        #expect(build(week).state == .completed(workoutID: run.id))
    }

    @Test("A reported session reads as completed")
    func completedAndReviewed() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)

        let run = try #require(week.orderedWorkouts.first)
        run.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 0, recoveryFeeling: .good))

        #expect(build(week).state == .completed(workoutID: run.id))
    }

    @Test("Skipped and missed stay distinct")
    func skippedAndMissed() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)

        let run = try #require(week.orderedWorkouts.first)
        run.skip()
        #expect(build(week).state == .skipped(workoutID: run.id))

        run.clearCompletion()
        // A day later the same untouched session is missed, not skipped.
        #expect(build(week, dayOffset: 1).state != .skipped(workoutID: run.id))
    }

    // MARK: - Non-training days

    @Test("A rest day is a rest day, not an empty workout day")
    func restDay() throws {
        let context = ModelContext(try container())
        let week = plan([.rest, .running], in: context)

        #expect(build(week).state == .restDay)
    }

    @Test("A day the plan never covered with nothing ahead is week complete")
    func weekComplete() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)

        #expect(build(week, dayOffset: 3).state == .weekComplete)
    }

    @Test("No plan is stated as such")
    func noPlan() {
        #expect(build(nil).state == .noPlan)
    }

    // MARK: - Next session

    @Test("The next session is the following training day")
    func nextSession() throws {
        let context = ModelContext(try container())
        let week = plan([.running, .rest, .swimming], in: context)

        let next = try #require(build(week).next)
        #expect(next.discipline == .swimming)
        // Rest days are not sessions, so they are skipped over.
        #expect(calendar.dateComponents([.day], from: monday, to: next.date).day == 2)
    }

    @Test("The last day of the week has nothing next")
    func noNextSession() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)

        #expect(build(week).next == nil)
    }

    // MARK: - Multiple sessions

    @Test("A remaining session dominates one already completed")
    func multipleSessions() throws {
        let context = ModelContext(try container())
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: monday,
            parameters: TrainingParameters()
        )
        context.insert(plan)

        let swim = PlannedWorkout(date: monday, discipline: .swimming, title: "Swim", prescribedDurationSeconds: 1_800)
        let ride = PlannedWorkout(date: monday, discipline: .cycling, title: "Ride", prescribedDurationSeconds: 2_400)
        context.insert(swim)
        context.insert(ride)
        plan.workouts.append(swim)
        plan.workouts.append(ride)

        swim.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))

        let presentation = build(plan)
        #expect(presentation.state == .upcoming(workoutID: ride.id))
        // §28: the finished session collapses into a summary rather than
        // disappearing.
        #expect(presentation.alsoCompletedToday == [swim.id])
    }

    @Test("Finished sessions are not listed once nothing is outstanding")
    func noOutstandingWork() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)

        let run = try #require(week.orderedWorkouts.first)
        run.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))

        #expect(build(week).alsoCompletedToday.isEmpty)
    }

    // MARK: - Helpers

    @Test("Outstanding states are the ones needing action")
    func outstandingStates() {
        #expect(TodayPresentationState.upcoming(workoutID: UUID()).isOutstanding)
        #expect(TodayPresentationState.needsFeedback(workoutID: UUID()).isOutstanding)
        #expect(TodayPresentationState.awaitingImport(workoutID: UUID()).isOutstanding)
        #expect(!TodayPresentationState.restDay.isOutstanding)
        #expect(!TodayPresentationState.loading.isOutstanding)
    }

    // MARK: - Finished on the Watch

    @Test("A session the Watch reports finished stops offering to start it")
    func awaitingImport() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)
        let run = try #require(week.orderedWorkouts.first)

        #expect(build(week).state == .upcoming(workoutID: run.id))
        #expect(build(week, finishedOnWatch: [run.id]).state == .awaitingImport(workoutID: run.id))
    }

    @Test("Once the import lands, feedback takes over from the waiting state")
    func importSupersedesWaiting() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)
        let run = try #require(week.orderedWorkouts.first)

        let summary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: monday,
            endDate: monday.addingTimeInterval(1_800),
            duration: 1_800,
            metrics: RecordedMetrics()
        )
        context.insert(summary)
        run.attach(summary)

        #expect(build(week, finishedOnWatch: [run.id]).state == .needsFeedback(workoutID: run.id))
    }

    @Test("A skipped session is not resurrected by a stale Watch entry")
    func skippedIgnoresWatch() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)
        let run = try #require(week.orderedWorkouts.first)
        run.skip()

        #expect(build(week, finishedOnWatch: [run.id]).state == .skipped(workoutID: run.id))
    }

    // MARK: - Edge cases

    @Test("A day before the plan begins rests rather than claiming the week is done")
    func beforeThePlanStarts() throws {
        let context = ModelContext(try container())
        let week = plan([.running, .rest, .swimming], in: context)

        let presentation = build(week, dayOffset: -1)
        #expect(presentation.state == .restDay)
        #expect(presentation.next != nil)
    }

    @Test("A skipped session does not hide one still to do")
    func skippedAlongsideOutstanding() throws {
        let context = ModelContext(try container())
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: monday,
            parameters: TrainingParameters()
        )
        context.insert(plan)

        let swim = PlannedWorkout(date: monday, discipline: .swimming, title: "Swim", prescribedDurationSeconds: 1_800)
        let ride = PlannedWorkout(date: monday, discipline: .cycling, title: "Ride", prescribedDurationSeconds: 2_400)
        context.insert(swim)
        context.insert(ride)
        plan.workouts.append(swim)
        plan.workouts.append(ride)

        swim.skip()

        #expect(build(plan).state == .upcoming(workoutID: ride.id))
    }

    @Test("An imported session with no report asks for feedback, not a verdict")
    func importedWithoutReport() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)
        let run = try #require(week.orderedWorkouts.first)

        let summary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: monday,
            endDate: monday.addingTimeInterval(1_500),
            duration: 1_500,
            metrics: RecordedMetrics()
        )
        context.insert(summary)
        run.attach(summary)

        #expect(build(week).state == .needsFeedback(workoutID: run.id))
    }

    @Test("A session that fell short of the prescription is still complete once reported")
    func partialSession() throws {
        let context = ModelContext(try container())
        let week = plan([.running], in: context)
        let run = try #require(week.orderedWorkouts.first)

        let summary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: monday,
            // Half of the prescribed 1,800 seconds.
            endDate: monday.addingTimeInterval(900),
            duration: 900,
            metrics: RecordedMetrics()
        )
        context.insert(summary)
        run.attach(summary)
        run.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 0, recoveryFeeling: .good))

        #expect(build(week).state == .completed(workoutID: run.id))
        #expect(run.recordedCompletion < 1)
    }
}

/// §5–7: the supporting lines must stay silent rather than invent a number.
@Suite("Today summaries")
struct TodayWorkoutSummaryTests {

    @Test("A session with no steps has no structure line")
    func noSteps() {
        let workout = PlannedWorkout(date: .now, discipline: .running, title: "Easy run")
        #expect(WorkoutStructureSummary.text(for: workout) == nil)
    }

    @Test("A step with neither duration nor distance is omitted, not shown as zero")
    func unmeasuredStep() {
        let workout = PlannedWorkout(date: .now, discipline: .running, title: "Easy run")
        let step = WorkoutStep(order: 0, kind: .work, title: "Main set")
        workout.steps.append(step)

        #expect(WorkoutStructureSummary.text(for: workout) == nil)
    }

    @Test("Effort has nothing to say without a target")
    func effortWithoutTarget() {
        #expect(TodayEffort.text(for: nil) == nil)
        #expect(TodayEffort.text(for: RPERange(3, 4))?.hasPrefix("Easy") == true)
        #expect(TodayEffort.text(for: RPERange(7, 8))?.hasPrefix("Hard") == true)
    }

    @Test("A rest day gets no coaching cue")
    func cueForRestDay() {
        let rest = PlannedWorkout(date: .now, discipline: .rest, title: "Rest")
        #expect(TodayCoachingCue.text(for: rest) == nil)

        let run = PlannedWorkout(date: .now, discipline: .running, title: "Run", targetRPE: RPERange(3, 4))
        #expect(TodayCoachingCue.text(for: run) != nil)
    }
}
