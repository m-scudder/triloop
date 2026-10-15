import Foundation
import Testing
@testable import Athevia

@MainActor
@Suite("Workout execution")
struct WorkoutExecutionTests {

    @Test("Repeat blocks expand into the exact player sequence")
    func expandsRepeats() {
        let workout = PlannedWorkout(
            date: .now,
            discipline: .running,
            title: "Run / Walk",
            steps: [
                .warmUp(order: 0, title: "Warm up", durationSeconds: 300),
                .repeating(
                    order: 1,
                    title: "Intervals",
                    count: 2,
                    children: [
                        WorkoutStep(order: 0, kind: .work, title: "Run", durationSeconds: 60),
                        WorkoutStep(order: 1, kind: .recovery, title: "Walk", durationSeconds: 30)
                    ]
                ),
                .cooldown(order: 2, title: "Cool down", durationSeconds: 180)
            ]
        )

        let plan = WorkoutExecutionPlan(workout: workout)

        #expect(plan.steps.map(\.title) == ["Warm up", "Run", "Walk", "Run", "Walk", "Cool down"])
        #expect(plan.steps[1].repetitionLabel == "Round 1 of 2")
        #expect(plan.steps[3].repetitionLabel == "Round 2 of 2")
    }


    @Test("Phone execution preserves multisport segment kinds")
    func multisportExecutionPlanPreservesSegments() {
        let workout = PlannedWorkout(
            date: .now,
            discipline: .multisport,
            title: "Bike + Run Brick",
            steps: [
                WorkoutStep(
                    order: 0,
                    kind: .cyclingSegment,
                    title: "Bike",
                    durationSeconds: 1_200
                ),
                WorkoutStep(
                    order: 1,
                    kind: .transition,
                    title: "Transition",
                    durationSeconds: 180
                ),
                WorkoutStep(
                    order: 2,
                    kind: .runningSegment,
                    title: "Run",
                    durationSeconds: 600
                )
            ]
        )

        let execution = WorkoutExecutionPlan(workout: workout)

        #expect(execution.steps.map(\.kind) == [.cyclingSegment, .transition, .runningSegment])
        #expect(execution.steps[0].kind.segmentSport == .cycling)
        #expect(execution.steps[1].kind.isTransition)
        #expect(execution.steps[2].kind.segmentSport == .running)
    }

    @Test("Countdown steps advance automatically")
    func countdownAdvances() {
        let enginePlan = plan(
            .warmUp(order: 0, title: "Warm up", durationSeconds: 10),
            WorkoutStep(order: 1, kind: .work, title: "Run", durationSeconds: 5)
        )
        let start = Date(timeIntervalSince1970: 1_000)
        var engine = WorkoutExecutionEngine(plan: enginePlan)

        engine.start(now: start)
        engine.advance(by: 12, now: start.addingTimeInterval(12))

        #expect(engine.currentIndex == 1)
        #expect(engine.stepElapsedSeconds == 2)
        #expect(engine.elapsedSeconds == 12)
        #expect(engine.phase == .running)

        engine.advance(by: 3, now: start.addingTimeInterval(15))
        #expect(engine.phase == .finished)
        #expect(engine.result?.elapsedSeconds == 15)
    }

    @Test("Elapsed background time can finish all timed steps")
    func timedWorkoutFinishesFromElapsedTime() {
        let start = Date(timeIntervalSince1970: 1_000)
        var engine = WorkoutExecutionEngine(plan: plan(
            WorkoutStep(order: 0, kind: .work, title: "Run", durationSeconds: 10),
            WorkoutStep(order: 1, kind: .recovery, title: "Walk", durationSeconds: 10),
            WorkoutStep(order: 2, kind: .work, title: "Run again", durationSeconds: 10)
        ))

        engine.start(now: start)
        engine.advance(by: 30, now: start.addingTimeInterval(30))

        #expect(engine.phase == .finished)
        #expect(engine.result?.elapsedSeconds == 30)
    }

    @Test("Elapsed time never completes a manual step")
    func elapsedTimeStopsAtManualStep() {
        let start = Date(timeIntervalSince1970: 1_000)
        var engine = WorkoutExecutionEngine(plan: plan(
            WorkoutStep(order: 0, kind: .work, title: "Run", durationSeconds: 10),
            WorkoutStep(order: 1, kind: .work, title: "Swim 100m", distanceMeters: 100),
            WorkoutStep(order: 2, kind: .cooldown, title: "Cool down", durationSeconds: 10)
        ))

        engine.start(now: start)
        engine.advance(by: 30, now: start.addingTimeInterval(30))

        #expect(engine.phase == .running)
        #expect(engine.currentIndex == 1)
        #expect(engine.currentStep?.title == "Swim 100m")
        #expect(engine.stepElapsedSeconds == 20)
    }

    @Test("Completing a paused set starts the next set")
    func pausedCompletionStartsNextSet() {
        var engine = WorkoutExecutionEngine(plan: plan(
            WorkoutStep(order: 0, kind: .work, title: "Swim 100m", distanceMeters: 100),
            WorkoutStep(order: 1, kind: .recovery, title: "Rest", durationSeconds: 30)
        ))

        engine.start()
        engine.advance(by: 20)
        engine.pause()
        engine.completeCurrentStep()

        #expect(engine.currentIndex == 1)
        #expect(engine.currentStep?.title == "Rest")
        #expect(engine.stepElapsedSeconds == 0)
        #expect(engine.phase == .running)
    }

    @Test("Paused time does not count")
    func pauseStopsClock() {
        var engine = WorkoutExecutionEngine(plan: plan(
            WorkoutStep(order: 0, kind: .work, title: "Ride", durationSeconds: 60)
        ))

        engine.start()
        engine.advance(by: 10)
        engine.pause()
        engine.advance(by: 30)

        #expect(engine.elapsedSeconds == 10)
        #expect(engine.stepElapsedSeconds == 10)

        engine.resume()
        engine.advance(by: 5)
        #expect(engine.elapsedSeconds == 15)
    }

    @Test("Distance steps advance automatically when the target is reached")
    func distanceStepAdvancesFromRecordedDistance() {
        var engine = WorkoutExecutionEngine(plan: plan(
            WorkoutStep(order: 0, kind: .work, title: "Run 100m", distanceMeters: 100)
        ))

        engine.start()
        engine.advance(by: 45)
        engine.updateCurrentStepDistance(60)

        #expect(engine.phase == .running)
        #expect(engine.currentStep?.usesCountdown == false)
        #expect(engine.stepElapsedSeconds == 45)
        #expect(engine.stepDistanceMeters == 60)
        #expect(engine.remainingDistanceMeters == 40)
        #expect(engine.remainingSeconds == nil)

        engine.updateCurrentStepDistance(100)
        #expect(engine.phase == .finished)
        #expect(engine.result?.elapsedSeconds == 45)
    }


    @Test("Workout-level duration creates an executable fallback step")
    func workoutLevelDurationDoesNotAutoComplete() {
        let workout = PlannedWorkout(
            date: .now,
            discipline: .running,
            title: "Easy Run",
            prescribedDurationSeconds: 600
        )
        let plan = WorkoutExecutionPlan(workout: workout)
        var engine = WorkoutExecutionEngine(plan: plan)

        #expect(plan.steps.count == 1)
        #expect(plan.steps.first?.durationSeconds == 600)

        engine.start()
        #expect(engine.phase == .running)

        engine.advance(by: 1)
        #expect(engine.phase == .running)
        #expect(engine.elapsedSeconds == 1)
    }


    @Test("Zero-duration structured steps do not auto-complete")
    func zeroDurationStepBecomesManual() {
        let workout = PlannedWorkout(
            date: .now,
            discipline: .running,
            title: "Broken Duration",
            steps: [
                WorkoutStep(
                    order: 0,
                    kind: .work,
                    title: "Run",
                    durationSeconds: 0
                )
            ]
        )
        let plan = WorkoutExecutionPlan(workout: workout)
        var engine = WorkoutExecutionEngine(plan: plan)

        #expect(plan.steps.count == 1)
        #expect(plan.steps.first?.durationSeconds == nil)

        engine.start()
        engine.advance(by: 5)

        #expect(engine.phase == .running)
        #expect(engine.elapsedSeconds == 5)
    }

    @Test("Unstructured workout without totals stays manual until user completes it")
    func emptyPrescriptionStaysManual() {
        let workout = PlannedWorkout(
            date: .now,
            discipline: .running,
            title: "Free Run"
        )
        let plan = WorkoutExecutionPlan(workout: workout)
        var engine = WorkoutExecutionEngine(plan: plan)

        #expect(plan.steps.count == 1)
        #expect(plan.steps.first?.durationSeconds == nil)
        #expect(plan.steps.first?.distanceMeters == nil)

        engine.start()
        engine.advance(by: 5)

        #expect(engine.phase == .running)
        #expect(engine.elapsedSeconds == 5)
    }

    private func plan(_ steps: WorkoutStep...) -> WorkoutExecutionPlan {
        WorkoutExecutionPlan(
            workout: PlannedWorkout(
                date: .now,
                discipline: .running,
                title: "Test",
                steps: steps
            )
        )
    }
}
