import Foundation
import Testing

@testable import TriLoop

@Suite("Weekly analysis")
struct WeeklyAnalysisTests {
    private let analyser = WeeklyAnalyser()

    /// Full availability keeps the canonical three-sport week these tests describe.
    private func seedPlan() -> WeeklyPlan {
        SeedWeekOne.makePlan()
    }

    private func sessions(_ plan: WeeklyPlan, for sport: Sport) -> [PlannedWorkout] {
        plan.trainingSessions.filter { $0.discipline.sport == sport }
    }

    private func completeEverything(_ plan: WeeklyPlan, with draft: FeedbackDraft) {
        for workout in plan.trainingSessions {
            workout.recordCompletion(with: draft)
        }
    }

    @Test("Only training sessions are counted")
    func restAndRecoveryAreExcluded() {
        let analysis = analyser.analyse(seedPlan())

        #expect(analysis.plannedSessions == 6)
        #expect(analysis.completedSessions == 0)
        #expect(analysis.sports.map(\.sport) == [.running, .swimming, .cycling])
    }

    @Test("An easy, fully completed week progresses every sport")
    func easyWeekProgresses() {
        let plan = seedPlan()
        completeEverything(plan, with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))

        let analysis = analyser.analyse(plan)

        #expect(analysis.completedSessions == 6)
        #expect(analysis.completedEverySession)
        #expect(analysis.isReadyForNextWeek)
        #expect(analysis.analysis(for: .running)?.status == .progress)
        #expect(analysis.analysis(for: .swimming)?.status == .progress)
        #expect(analysis.analysis(for: .cycling)?.status == .progress)
        #expect(analysis.analysis(for: .running)?.adjustment == .runIntervalDuration(deltaSeconds: 15))
        #expect(analysis.analysis(for: .cycling)?.adjustment == .rideDuration(deltaSeconds: 300))
    }

    @Test("The most cautious session governs the sport")
    func worstSessionGovernsTheWeek() {
        let plan = seedPlan()
        let runs = sessions(plan, for: .running)
        runs[0].recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        runs[1].recordCompletion(with: FeedbackDraft(rpe: 8, painScore: 5, painLocations: [.shin]))

        let running = analyser.analyse(plan).analysis(for: .running)

        #expect(running?.status == .reduce)
        #expect(running?.completedSessions == 2)
    }

    @Test("An unfinished sport cannot progress")
    func missedSessionBlocksProgression() {
        let plan = seedPlan()
        sessions(plan, for: .running)[0].recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))

        let running = analyser.analyse(plan).analysis(for: .running)

        #expect(running?.status == .maintain)
        #expect(running?.adjustment == .hold)
        #expect(running?.completedSessions == 1)
        #expect(running?.plannedSessions == 2)
        #expect(running?.completedEverySession == false)
        #expect(running?.reasons.contains(.sessionsMissed(count: 1)) == true)
    }

    @Test("A sport with no reports holds rather than guessing")
    func unreportedSportHolds() {
        let analysis = analyser.analyse(seedPlan())
        let cycling = analysis.analysis(for: .cycling)

        #expect(cycling?.status == .maintain)
        #expect(cycling?.adjustment == .hold)
        #expect(cycling?.averageRPE == nil)
        #expect(cycling?.reasons.contains(.sessionsMissed(count: 2)) == true)
        #expect(analysis.isReadyForNextWeek == false)
    }

    @Test("Effort is averaged across a sport's sessions")
    func effortIsAveraged() {
        let plan = seedPlan()
        let swims = sessions(plan, for: .swimming)
        swims[0].recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        swims[1].recordCompletion(with: FeedbackDraft(rpe: 5, painScore: 2))

        let swimming = analyser.analyse(plan).analysis(for: .swimming)

        #expect(swimming?.averageRPE == 4.0)
        #expect(swimming?.highestPain == 2)
    }

    @Test("Swimming volume is totalled in metres")
    func swimmingVolumeIsTotalled() {
        let plan = seedPlan()
        for swim in sessions(plan, for: .swimming) {
            swim.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 0))
        }

        let swimming = analyser.analyse(plan).analysis(for: .swimming)

        #expect(swimming?.totalDistanceMeters == 600)
    }

    @Test("Severe pain sends the sport to recovery")
    func severePainOverridesTheWeek() {
        let plan = seedPlan()
        completeEverything(plan, with: FeedbackDraft(rpe: 2, painScore: 9))

        let analysis = analyser.analyse(plan)

        #expect(analysis.analysis(for: .running)?.status == .recoveryRequired)
        #expect(analysis.analysis(for: .running)?.adjustment == .substituteRecovery)
    }

    @Test("A skipped session lets the week close without counting as done")
    func skippedSessionClosesTheWeek() {
        let plan = seedPlan()
        let all = plan.trainingSessions
        for workout in all.dropLast() {
            workout.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        }
        all.last?.skip()

        let analysis = analyser.analyse(plan)

        #expect(analysis.skippedSessions == 1)
        #expect(analysis.completedSessions == all.count - 1)
        #expect(analysis.isReadyForNextWeek)
        #expect(analysis.completedEverySession == false)
    }

    @Test("Skipping still blocks progression for that sport")
    func skippingBlocksProgression() {
        let plan = seedPlan()
        let runs = sessions(plan, for: .running)
        runs[0].recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))
        runs[1].skip()

        let running = analyser.analyse(plan).analysis(for: .running)

        #expect(running?.status == .maintain)
        #expect(running?.adjustment == .hold)
        #expect(running?.reasons.contains(.sessionsMissed(count: 1)) == true)
    }

    @Test("An unresolved past session is missed, a future one is not")
    func missedIsDerivedFromTheDate() {
        let plan = seedPlan()
        guard let session = plan.trainingSessions.first else { return }
        let calendar = Calendar.current
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: session.date) ?? session.date

        #expect(session.isMissed(asOf: dayAfter))
        #expect(session.isMissed(asOf: session.date) == false)
    }

    @Test("A reported or skipped session is never missed")
    func resolvedSessionsAreNotMissed() {
        let plan = seedPlan()
        let all = plan.trainingSessions
        let calendar = Calendar.current
        guard let reported = all.first, let skipped = all.last else { return }
        let later = calendar.date(byAdding: .day, value: 30, to: reported.date) ?? reported.date

        reported.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        skipped.skip()

        #expect(reported.isMissed(asOf: later) == false)
        #expect(skipped.isMissed(asOf: later) == false)
    }
}
