import Foundation
import Testing
@testable import TriLoop

@Suite("Training signals")
struct TrainingSignalsTests {

    private let monday = Date(timeIntervalSince1970: 1_760_000_000)

    private func session(_ sport: Sport, load: Double?, minutes: Double = 45, dayOffset: Int = 0, week: Int = 0) -> LoadedSession {
        LoadedSession(
            date: monday.addingTimeInterval(Double(week * 7 + dayOffset) * 86_400),
            sport: sport,
            load: load.map { SessionLoad(value: $0, provenance: .reportedEffort) },
            durationSeconds: minutes * 60,
            intensity: .easy
        )
    }

    private func week(_ number: Int, _ sessions: [LoadedSession]) -> PlanWeekSessions {
        PlanWeekSessions(
            weekNumber: number,
            startDate: monday.addingTimeInterval(Double(number - 1) * 7 * 86_400),
            sessions: sessions
        )
    }

    @Test("Workload carries current, previous and the change between them")
    func workload() throws {
        let signals = TrainingSignalsBuilder.build(
            weeks: [
                week(1, [session(.running, load: 200, week: 0)]),
                week(2, [session(.running, load: 300, week: 1)])
            ],
            recovery: [:],
            asOf: monday
        )

        #expect(signals.workload.currentWeek == .available(300))
        #expect(signals.workload.previousWeek == .available(200))
        #expect(abs((signals.workload.weekOnWeekChange ?? 0) - 0.5) < 0.0001)
    }

    @Test("A four-week average needs four weeks")
    func averageNeedsFourWeeks() {
        let signals = TrainingSignalsBuilder.build(
            weeks: [week(1, [session(.running, load: 200)])],
            recovery: [:],
            asOf: monday
        )
        #expect(!signals.workload.fourWeekAverage.isAvailable)
    }

    @Test("Groups stay independently available")
    func partialSignals() {
        // Workouts but no wearable: workload exists, recovery does not, and one
        // must not suppress the other.
        let signals = TrainingSignalsBuilder.build(
            weeks: [week(1, [session(.running, load: 200)])],
            recovery: [:],
            asOf: monday
        )
        #expect(!signals.workload.isEmpty)
        #expect(signals.recovery.isEmpty)
        #expect(!signals.isEmpty)
    }

    @Test("Nothing measured leaves the signals empty")
    func emptySignals() {
        let signals = TrainingSignalsBuilder.build(weeks: [], recovery: [:], asOf: monday)
        #expect(signals.isEmpty)
    }

    @Test("Recovery readings outside the usual range are listed")
    func recoveryStandings() throws {
        let rising = (0..<6).map { index in
            RecoveryReading(
                date: monday.addingTimeInterval(-Double(6 - index) * 86_400),
                value: index == 5 ? 70 : 50
            )
        }

        let signals = TrainingSignalsBuilder.build(
            weeks: [],
            recovery: [.restingHeartRate: rising],
            asOf: monday
        )

        #expect(signals.recovery.outsideUsualRange == [.restingHeartRate])
        #expect(signals.recovery.standings[.restingHeartRate] == .above)
    }

    @Test("Change against the settled average is preferred to one week")
    func changeAgainstAverage() throws {
        var workload = WorkloadSignals()
        workload.currentWeek = .available(500)
        workload.fourWeekAverage = .available(400)
        #expect(abs((workload.changeAgainstAverage ?? 0) - 0.25) < 0.0001)
    }
}

@Suite("Shadow evaluation")
struct ShadowEvaluationTests {

    private func signals(
        change: Double? = nil,
        aboveTarget: Int = 0,
        standings: [RecoveryMetricKey: BaselineStanding] = [:]
    ) -> TrainingSignals {
        var workload = WorkloadSignals()
        workload.currentWeek = .available(400)
        workload.weekOnWeekChange = change

        return TrainingSignals(
            workload: workload,
            adherence: AdherenceSignals(
                outcomes: Array(repeating: .aboveTarget, count: aboveTarget)
            ),
            intensity: IntensitySignals(),
            recovery: RecoverySignals(
                baselines: standings.mapValues { _ in
                    PhysiologicalBaseline(window: .sevenDay, average: 50, readingCount: 5, latest: 55)
                },
                standings: standings
            ),
            performance: PerformanceSignals()
        )
    }

    @Test("A settled week agrees with the engine")
    func agrees() {
        let observation = ShadowEvaluator.evaluate(signals: signals(change: 0.05), engineDecision: "progress")
        #expect(observation.suggestion == .agrees)
    }

    @Test("One concern suggests maintain")
    func oneConcern() {
        let observation = ShadowEvaluator.evaluate(signals: signals(change: 0.30), engineDecision: "progress")
        #expect(observation.suggestion == .maintainMayBeMoreAppropriate)
        #expect(observation.reasons.contains { $0.contains("30%") })
    }

    @Test("Several concerns suggest reduce")
    func severalConcerns() {
        let observation = ShadowEvaluator.evaluate(
            signals: signals(change: 0.30, aboveTarget: 2, standings: [.heartRateVariability: .below]),
            engineDecision: "progress"
        )
        #expect(observation.suggestion == .reduceMayBeMoreAppropriate)
    }

    @Test("Direction matters: a high resting heart rate counts, a high HRV does not")
    func directionOfConcern() {
        let worrying = ShadowEvaluator.evaluate(
            signals: signals(standings: [.restingHeartRate: .above]),
            engineDecision: "progress"
        )
        #expect(worrying.suggestion == .maintainMayBeMoreAppropriate)

        let favourable = ShadowEvaluator.evaluate(
            signals: signals(standings: [.heartRateVariability: .above]),
            engineDecision: "progress"
        )
        // Still reported, but a rise in HRV is not a reason for caution.
        #expect(favourable.suggestion == .agrees)
        #expect(favourable.reasons.contains { $0.contains("HRV") })
    }

    @Test("No evidence is stated as such, not as agreement")
    func insufficientEvidence() {
        let empty = TrainingSignals(
            workload: WorkloadSignals(),
            adherence: AdherenceSignals(),
            intensity: IntensitySignals(),
            recovery: RecoverySignals(),
            performance: PerformanceSignals()
        )
        let observation = ShadowEvaluator.evaluate(signals: empty, engineDecision: "progress")
        #expect(observation.suggestion == .insufficientEvidence)
    }

    @Test("The engine's decision is carried through untouched")
    func engineDecisionPreserved() {
        // §52: the shadow observes, it never replaces.
        let observation = ShadowEvaluator.evaluate(
            signals: signals(change: 0.40, aboveTarget: 3),
            engineDecision: "progress"
        )
        #expect(observation.engineDecision == "progress")
    }
}
