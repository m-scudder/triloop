import Foundation
import Testing
@testable import TriLoop

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

    @Test("Distance steps use a stopwatch until explicitly completed")
    func distanceStepIsManual() {
        var engine = WorkoutExecutionEngine(plan: plan(
            WorkoutStep(order: 0, kind: .work, title: "Swim 100m", distanceMeters: 100)
        ))

        engine.start()
        engine.advance(by: 45)

        #expect(engine.phase == .running)
        #expect(engine.currentStep?.usesCountdown == false)
        #expect(engine.stepElapsedSeconds == 45)
        #expect(engine.remainingSeconds == nil)

        engine.completeCurrentStep()
        #expect(engine.phase == .finished)
        #expect(engine.result?.elapsedSeconds == 45)
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
