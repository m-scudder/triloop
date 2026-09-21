import Foundation
import Testing

@testable import Athevia

@Suite("Watch workout execution")
struct WatchWorkoutExecutionTests {
    @Test("Repeat blocks flatten into concrete rounds")
    func repeatBlocksFlatten() {
        let work = WatchWorkoutStepPayload(
            id: UUID(),
            kind: .work,
            title: "Hard",
            instructions: nil,
            durationSeconds: 5,
            distanceMeters: nil,
            targetIntensity: .hard,
            repeatCount: nil,
            children: []
        )
        let recovery = WatchWorkoutStepPayload(
            id: UUID(),
            kind: .recovery,
            title: "Easy",
            instructions: nil,
            durationSeconds: 3,
            distanceMeters: nil,
            targetIntensity: .easy,
            repeatCount: nil,
            children: []
        )
        let repeatBlock = WatchWorkoutStepPayload(
            id: UUID(),
            kind: .repeatBlock,
            title: "Intervals",
            instructions: nil,
            durationSeconds: nil,
            distanceMeters: nil,
            targetIntensity: nil,
            repeatCount: 2,
            children: [work, recovery]
        )
        let workout = makeWorkout(steps: [repeatBlock])

        let plan = WatchWorkoutExecutionPlan(workout: workout)

        #expect(plan.steps.count == 4)
        #expect(plan.steps[0].repetition == 1)
        #expect(plan.steps[2].repetition == 2)
    }

    @Test("Timed steps advance automatically")
    func timedStepProgression() {
        let first = step(title: "Warm-up", duration: 10)
        let second = step(title: "Work", duration: 5)
        var engine = WatchWorkoutExecutionEngine(
            workout: makeWorkout(steps: [first, second])
        )

        engine.start()
        engine.advance(by: 10)

        #expect(engine.currentStep?.title == "Work")
        #expect(engine.phase == .running)

        engine.advance(by: 5)

        #expect(engine.phase == .finished)
    }

    @Test("Distance steps advance from live distance")
    func distanceStepProgression() {
        let distanceStep = WatchWorkoutStepPayload(
            id: UUID(),
            kind: .work,
            title: "Run",
            instructions: nil,
            durationSeconds: nil,
            distanceMeters: 100,
            targetIntensity: .steady,
            repeatCount: nil,
            children: []
        )
        var engine = WatchWorkoutExecutionEngine(
            workout: makeWorkout(steps: [distanceStep])
        )

        engine.start()
        engine.advance(by: 5, distanceDeltaMeters: 40)

        #expect(engine.remainingDistanceMeters == 60)

        engine.advance(by: 5, distanceDeltaMeters: 60)

        #expect(engine.phase == .finished)
    }

    private func step(title: String, duration: TimeInterval) -> WatchWorkoutStepPayload {
        WatchWorkoutStepPayload(
            id: UUID(),
            kind: .work,
            title: title,
            instructions: nil,
            durationSeconds: duration,
            distanceMeters: nil,
            targetIntensity: .steady,
            repeatCount: nil,
            children: []
        )
    }

    private func makeWorkout(steps: [WatchWorkoutStepPayload]) -> WatchWorkoutPayload {
        WatchWorkoutPayload(
            id: UUID(),
            date: .now,
            discipline: .running,
            title: "Test",
            goal: "",
            estimatedDurationSeconds: nil,
            estimatedDistanceMeters: nil,
            status: .planned,
            steps: steps
        )
    }
}
