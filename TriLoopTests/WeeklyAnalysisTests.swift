import Foundation
import Testing

@testable import TriLoop

@Suite("Weekly analysis")
struct WeeklyAnalysisTests {
    private let analyser = WeeklyAnalyser()

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
        let analysis = analyser.analyse(SeedWeekOne.makePlan())

        #expect(analysis.plannedSessions == 5)
        #expect(analysis.completedSessions == 0)
        #expect(analysis.sports.map(\.sport) == [.running, .swimming, .cycling])
    }

    @Test("An easy, fully completed week progresses every sport")
    func easyWeekProgresses() {
        let plan = SeedWeekOne.makePlan()
        completeEverything(plan, with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))

        let analysis = analyser.analyse(plan)

        #expect(analysis.completedSessions == 5)
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
        let plan = SeedWeekOne.makePlan()
        let runs = sessions(plan, for: .running)
        runs[0].recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        runs[1].recordCompletion(with: FeedbackDraft(rpe: 8, painScore: 5, painLocations: [.shin]))

        let running = analyser.analyse(plan).analysis(for: .running)

        #expect(running?.status == .reduce)
        #expect(running?.completedSessions == 2)
    }

    @Test("An unfinished sport cannot progress")
    func missedSessionBlocksProgression() {
        let plan = SeedWeekOne.makePlan()
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
        let analysis = analyser.analyse(SeedWeekOne.makePlan())
        let cycling = analysis.analysis(for: .cycling)

        #expect(cycling?.status == .maintain)
        #expect(cycling?.adjustment == .hold)
        #expect(cycling?.averageRPE == nil)
        #expect(cycling?.reasons.contains(.sessionsMissed(count: 1)) == true)
        #expect(analysis.isReadyForNextWeek == false)
    }

    @Test("Effort is averaged across a sport's sessions")
    func effortIsAveraged() {
        let plan = SeedWeekOne.makePlan()
        let swims = sessions(plan, for: .swimming)
        swims[0].recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        swims[1].recordCompletion(with: FeedbackDraft(rpe: 5, painScore: 2))

        let swimming = analyser.analyse(plan).analysis(for: .swimming)

        #expect(swimming?.averageRPE == 4.0)
        #expect(swimming?.highestPain == 2)
    }

    @Test("Swimming volume is totalled in metres")
    func swimmingVolumeIsTotalled() {
        let plan = SeedWeekOne.makePlan()
        for swim in sessions(plan, for: .swimming) {
            swim.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 0))
        }

        let swimming = analyser.analyse(plan).analysis(for: .swimming)

        #expect(swimming?.totalDistanceMeters == 600)
    }

    @Test("Severe pain sends the sport to recovery")
    func severePainOverridesTheWeek() {
        let plan = SeedWeekOne.makePlan()
        completeEverything(plan, with: FeedbackDraft(rpe: 2, painScore: 9))

        let analysis = analyser.analyse(plan)

        #expect(analysis.analysis(for: .running)?.status == .recoveryRequired)
        #expect(analysis.analysis(for: .running)?.adjustment == .substituteRecovery)
    }
}
