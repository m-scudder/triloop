import Foundation
import Testing
@testable import Athevia

@MainActor
@Suite("Workout audio coaching")
struct WorkoutCoachingTests {
    @Test("Coaching follows expanded repeats, recovery, and prescribed effort")
    func repeatedCues() throws {
        let plan = makePlan([
            .warmUp(order: 0, title: "Warm up", durationSeconds: 60),
            .repeating(order: 1, title: "Intervals", count: 2, children: [
                WorkoutStep(order: 0, kind: .work, title: "Run", instructions: "Relax your shoulders.", durationSeconds: 40, targetIntensity: .hard),
                WorkoutStep(order: 1, kind: .recovery, title: "Walk", durationSeconds: 20)
            ]),
            .cooldown(order: 2, title: "Cool down", durationSeconds: 60)
        ])
        let timeline = try #require(WorkoutCoachingTimeline(plan: plan, countdowns: true))

        #expect(timeline.stepStarts == [0, 60, 100, 120, 160, 180])
        #expect(timeline.duration == 240)
        #expect(timeline.cues.map(\.time) == [0, 50, 60, 90, 100, 120, 150, 160, 180, 230, 240])
        let secondRun = try #require(timeline.cues.first { $0.time == 120 })
        #expect(secondRun.text.contains("Round 2 of 2"))
        #expect(secondRun.text.contains("Hard effort"))
        #expect(secondRun.text.contains("Relax your shoulders."))
        #expect(timeline.cues.last?.text == "Workout complete. Well done.")
    }

    @Test("Countdowns can be disabled without losing step announcements")
    func countdownPreference() throws {
        let plan = makePlan([
            WorkoutStep(order: 0, kind: .work, title: "Cycle", durationSeconds: 90),
            WorkoutStep(order: 1, kind: .recovery, title: "Easy", durationSeconds: 15)
        ])
        let timeline = try #require(WorkoutCoachingTimeline(plan: plan, countdowns: false))
        #expect(timeline.cues.map(\.time) == [0, 90, 105])
        #expect(timeline.cues.first?.text.contains("1 minute and 30 seconds") == true)
    }

    @Test("Short sets do not get overlapping countdown announcements")
    func shortSets() throws {
        let timeline = try #require(WorkoutCoachingTimeline(plan: makePlan([
            WorkoutStep(order: 0, kind: .work, title: "Run", durationSeconds: 5),
            WorkoutStep(order: 1, kind: .recovery, title: "Walk", durationSeconds: 5)
        ]), countdowns: true))
        #expect(timeline.cues.map(\.time) == [0, 5, 10])
        #expect(timeline.cues.first?.briefText == "Run")
    }

    @Test("Manual, empty, invalid, and oversized prescriptions cannot become audio timelines")
    func invalidPlans() {
        #expect(WorkoutCoachingTimeline(plan: makePlan([]), countdowns: true) == nil)
        #expect(WorkoutCoachingTimeline(plan: makePlan([
            WorkoutStep(order: 0, kind: .work, title: "Run", distanceMeters: 400)
        ]), countdowns: true) == nil)
        for duration in [0, -1, Double.infinity, Double.nan, Double.greatestFiniteMagnitude] {
            #expect(WorkoutCoachingTimeline(plan: makePlan([
                WorkoutStep(order: 0, kind: .work, title: "Run", durationSeconds: duration)
            ]), countdowns: true) == nil)
        }
        #expect(WorkoutCoachingTimeline(plan: makePlan([
            WorkoutStep(order: 0, kind: .work, title: "Run", durationSeconds: 12_000),
            WorkoutStep(order: 1, kind: .work, title: "Run", durationSeconds: 12_000)
        ]), countdowns: true) == nil)
    }

    @Test("The playback clock catches up after lock without counting pauses or skips")
    func playbackClockTracksActiveTime() {
        var engine = WorkoutExecutionEngine(plan: makePlan([
            WorkoutStep(order: 0, kind: .work, title: "Run", durationSeconds: 60),
            WorkoutStep(order: 1, kind: .recovery, title: "Walk", durationSeconds: 30),
            WorkoutStep(order: 2, kind: .work, title: "Run", durationSeconds: 60)
        ]))
        var clock = WorkoutPlaybackClock()
        engine.start()
        engine.advance(by: clock.consume(10))
        engine.pause()
        #expect(clock.consume(10) == 0) // Paused media does not progress.
        engine.resume()
        engine.completeCurrentStep() // Skip the remaining 50 seconds.
        clock.seek(to: 60)
        engine.advance(by: clock.consume(95)) // One update after locking.

        #expect(engine.currentIndex == 2)
        #expect(engine.stepElapsedSeconds == 5)
        #expect(engine.elapsedSeconds == 45)
        #expect(clock.consume(0) == 0) // AVAudioPlayer may reset at EOF.
        engine.advance(by: clock.consume(150))
        #expect(engine.phase == .finished)
        #expect(engine.result?.elapsedSeconds == 100)
    }

    private func makePlan(_ steps: [WorkoutStep]) -> WorkoutExecutionPlan {
        WorkoutExecutionPlan(workout: PlannedWorkout(
            date: .now, discipline: .running, title: "Coached workout", steps: steps
        ))
    }
}
