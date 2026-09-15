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

    @Test("Manual-only positive reports cannot progress prescribed parameters", arguments: [WorkoutOrigin.custom, .library, .imported])
    func manualPositiveReportsHold(origin: WorkoutOrigin) throws {
        let plan = seedPlan()
        for workout in plan.trainingSessions {
            workout.origin = origin
        }
        completeEverything(plan, with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))

        let analysis = analyser.analyse(plan)

        #expect(analysis.plannedSessions == 0)
        #expect(analysis.completedSessions == 0)
        #expect(analysis.isReadyForNextWeek)
        #expect(analysis.sports.allSatisfy { $0.status == .maintain && $0.adjustment == .hold })
        #expect(try #require(analysis.analysis(for: .running)).totalDurationSeconds > 0)
    }

    @Test("Manual safety feedback still constrains its sport", arguments: [WorkoutOrigin.custom, .library, .imported])
    func manualSafetyOverrides(origin: WorkoutOrigin) throws {
        let plan = seedPlan()
        completeEverything(plan, with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))
        let manual = PlannedWorkout(
            date: plan.startDate,
            discipline: .running,
            title: "Additional run",
            prescribedDurationSeconds: 1_800,
            origin: origin
        )
        plan.workouts.append(manual)
        manual.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 2))

        let held = analyser.analyse(plan)
        #expect(held.completedSessions == 6)
        #expect(held.plannedSessions == 6)
        #expect(held.analysis(for: .running)?.status == .maintain)
        #expect(held.analysis(for: .running)?.reasons.contains(.painReported(score: 2)) == true)
        #expect(held.analysis(for: .cycling)?.status == .progress)

        manual.recordCompletion(with: FeedbackDraft(rpe: 8, painScore: 5))
        #expect(analyser.analyse(plan).analysis(for: .running)?.status == .reduce)

        manual.recordRecoveryCheckIn(painScore: 8, soreness: .mild, energy: .normal)
        let recovery = try #require(analyser.analyse(plan).analysis(for: .running))
        #expect(recovery.status == .recoveryRequired)
        #expect(recovery.reasons.contains(.nextDayPain(score: 8)))
    }

    @Test("Three generated reports out of five stay three out of five with manual additions", arguments: [WorkoutOrigin.custom, .library, .imported])
    func mixedWeekCounts(origin: WorkoutOrigin) throws {
        let workouts = (0..<7).map { offset in
            PlannedWorkout(
                date: Date(timeIntervalSince1970: 1_760_000_000 + Double(offset) * 86_400),
                discipline: .running,
                title: "Run",
                prescribedDurationSeconds: 1_800,
                origin: offset < 5 ? .generated : origin
            )
        }
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: workouts[0].date,
            endDate: workouts[6].date,
            workouts: workouts
        )
        for workout in Array(workouts.prefix(3)) + Array(workouts.suffix(2)) {
            workout.recordCompletion(with: FeedbackDraft())
        }
        workouts[3].skip()

        let analysis = analyser.analyse(plan)
        let running = try #require(analysis.analysis(for: .running))

        #expect(analysis.plannedSessions == 5)
        #expect(analysis.completedSessions == 3)
        #expect(analysis.skippedSessions == 1)
        #expect(!analysis.isReadyForNextWeek)
        #expect(running.plannedSessions == 5)
        #expect(running.completedSessions == 3)
        #expect(running.reasons.contains(.sessionsMissed(count: 2)))
        #expect(running.status == .maintain)
        #expect(running.totalDurationSeconds == 9_000)
        #expect(running.averageRPE == 3)
    }

    @Test("Unreported or skipped manual additions do not hold a finished generated week open", arguments: [WorkoutOrigin.custom, .library, .imported])
    func manualResolutionDoesNotAffectReadiness(origin: WorkoutOrigin) {
        let plan = seedPlan()
        completeEverything(plan, with: FeedbackDraft())
        let manual = PlannedWorkout(
            date: plan.startDate,
            discipline: .running,
            title: "Additional run",
            origin: origin
        )
        plan.workouts.append(manual)

        for shouldSkip in [false, true] {
            if shouldSkip { manual.skip() }
            let analysis = analyser.analyse(plan)
            #expect(analysis.isReadyForNextWeek)
            #expect(analysis.completedEverySession)
            #expect(analysis.skippedSessions == 0)
            #expect(analysis.analysis(for: .running)?.status == .progress)
        }
    }

    @Test("Manual additions cannot increase next week's prescribed frequency", arguments: [WorkoutOrigin.custom, .library, .imported])
    func manualAdditionsDoNotBecomePrescriptions(origin: WorkoutOrigin) {
        let plan = seedPlan()
        completeEverything(plan, with: FeedbackDraft())
        let generator = WeeklyPlanGenerator()
        let baseline = generator.generate(after: plan, analysis: analyser.analyse(plan))
        let manual = PlannedWorkout(
            date: plan.startDate,
            discipline: .running,
            title: "Additional run",
            prescribedDurationSeconds: 1_800,
            origin: origin
        )
        manual.recordCompletion(with: FeedbackDraft())
        plan.workouts.append(manual)

        let next = generator.generate(after: plan, analysis: analyser.analyse(plan))

        #expect(next.parameters == baseline.parameters)
        #expect(next.trainingSessions.map(\.discipline) == baseline.trainingSessions.map(\.discipline))
    }

    @Test("Manual next-day caution and warning symptoms govern even without a generated session in that sport", arguments: [WorkoutOrigin.custom, .library, .imported])
    func manualOnlySportRetainsSafety(origin: WorkoutOrigin) throws {
        let plan = seedPlan()
        let runs = sessions(plan, for: .running)
        for run in runs {
            run.origin = origin
            run.recordCompletion(with: FeedbackDraft())
        }
        runs[0].recordRecoveryCheckIn(painScore: 0, soreness: .significant, energy: .low)

        let held = try #require(analyser.analyse(plan).analysis(for: .running))
        #expect(held.plannedSessions == 0)
        #expect(held.status == .maintain)
        #expect(held.reasons.contains(.lingeringSoreness(.significant)))
        #expect(held.reasons.contains(.lowEnergyNextDay(.low)))

        let symptom = try #require(WarningSymptom.allCases.first)
        runs[0].recordCompletion(with: FeedbackDraft(symptoms: [symptom]))
        let analysis = analyser.analyse(plan)
        let recovery = try #require(analysis.analysis(for: .running))
        #expect(recovery.status == .recoveryRequired)
        #expect(recovery.reasons.contains(.warningSymptom(symptom)))
        #expect(recovery.adjustment == .substituteRecovery)

        let next = WeeklyPlanGenerator().generate(after: plan, analysis: analysis)
        #expect(next.trainingSessions.allSatisfy { $0.discipline.sport != .running })
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
