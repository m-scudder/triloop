import Foundation
import Testing
@testable import TriLoop

/// §5 and §10: one workout must not be read differently depending on which
/// feature asks. These exercise the shared path directly, which is the only
/// path any caller now uses.
@Suite("Intelligence consistency")
struct IntelligenceConsistencyTests {

    private let start = Date(timeIntervalSince1970: 1_760_000_000)
    private let ceiling: Double = 180

    private func readings(_ values: [Double], secondsApart: TimeInterval = 60) -> [HeartRateReading] {
        values.enumerated().map { index, bpm in
            HeartRateReading(
                date: start.addingTimeInterval(Double(index) * secondsApart),
                beatsPerMinute: bpm
            )
        }
    }

    private func evidence(
        samples: [HeartRateReading] = [],
        averageHeartRate: Double? = nil,
        reportedRPE: Int? = nil,
        appleEffort: Double? = nil,
        minutes: Double = 30,
        planned: Double? = nil,
        target: RPERange? = nil,
        completion: ExecutionComparison.Completion = .recorded
    ) -> WorkoutEvidence {
        WorkoutEvidence(
            date: start,
            sport: .running,
            durationSeconds: minutes * 60,
            averageHeartRate: averageHeartRate,
            heartRateSamples: samples,
            effort: EffortEvidence(
                targetRPE: target?.upper,
                reportedRPE: reportedRPE,
                estimatedHealthKitEffort: appleEffort
            ),
            plannedDurationSeconds: planned.map { $0 * 60 },
            targetRPE: target,
            completion: completion
        )
    }

    private func interpret(_ evidence: WorkoutEvidence) -> WorkoutInterpretation {
        WorkoutIntelligence.interpret(evidence, maximumHeartRate: ceiling)
    }

    // MARK: - Determinism across callers

    @Test("The same evidence always produces the same interpretation")
    func sameEvidenceSameResult() {
        let item = evidence(samples: readings([100, 140, 150, 160]), reportedRPE: 5)

        let first = interpret(item)
        let second = interpret(item)

        #expect(first.zones == second.zones)
        #expect(first.intensity == second.intensity)
        #expect(first.load == second.load)
        #expect(first.adherence == second.adherence)
    }

    // MARK: - Evidence matrix (§10)

    @Test("Heart-rate zones and effort together read as hybrid")
    func zonesAndEffort() throws {
        let result = interpret(evidence(samples: readings([100, 105, 100, 102]), reportedRPE: 3))
        let load = try #require(result.load.value)
        #expect(load.provenance == .hybrid)
        #expect(result.zones != nil)
    }

    @Test("Heart-rate zones alone read as heart rate")
    func zonesOnly() throws {
        let result = interpret(evidence(samples: readings([100, 105, 100, 102])))
        #expect(try #require(result.load.value).provenance == .heartRate)
    }

    @Test("Reported effort alone reads as reported effort")
    func effortOnly() throws {
        let result = interpret(evidence(reportedRPE: 6))
        #expect(try #require(result.load.value).provenance == .reportedEffort)
    }

    @Test("Apple's effort alone reads as HealthKit effort")
    func appleEffortOnly() throws {
        let result = interpret(evidence(appleEffort: 7))
        #expect(try #require(result.load.value).provenance == .healthKitEffort)
    }

    @Test("Conflicting heart rate and effort take the harder reading")
    func conflicting() throws {
        let result = interpret(evidence(samples: readings([100, 102, 101, 100]), reportedRPE: 9))
        let reading = try #require(result.intensity.value)
        #expect(reading.intensity == .hard)
        #expect(reading.evidence == .conflicting)
    }

    @Test("No usable evidence is unavailable, never zero")
    func noEvidence() {
        let result = interpret(evidence())
        #expect(result.intensity == .unavailable)
        #expect(result.load == .unavailable)
        #expect(result.load.value?.value != 0)
    }

    // MARK: - Zones preferred over averages (§4)

    @Test("A heart-rate series is preferred to an average")
    func seriesBeatsAverage() throws {
        // The average says easy; the series shows most of the session above
        // 80% of maximum. Time in zone must win.
        let result = interpret(
            evidence(
                samples: readings([170, 170, 170, 90]),
                averageHeartRate: 100
            )
        )
        #expect(result.zones != nil)
        #expect(try #require(result.intensity.value).intensity == .hard)
    }

    @Test("An average is used only when no series exists")
    func averageIsFallback() throws {
        let result = interpret(evidence(averageHeartRate: 170))
        #expect(result.zones == nil)
        #expect(try #require(result.intensity.value).intensity == .hard)
        // Still heart-rate evidence, just weaker.
        #expect(try #require(result.intensity.value).evidence == .heartRateZones)
    }

    @Test("Without a ceiling there are no zones and no heart-rate reading")
    func noCeiling() {
        let result = WorkoutIntelligence.interpret(
            evidence(samples: readings([100, 140, 160])),
            maximumHeartRate: nil
        )
        #expect(result.zones == nil)
        #expect(result.intensity == .unavailable)
    }

    // MARK: - Adherence reaches the interpretation (§1)

    @Test("Adherence is part of every interpretation")
    func adherenceIncluded() throws {
        let result = interpret(
            evidence(reportedRPE: 8, minutes: 30, planned: 30, target: RPERange(3, 4))
        )
        let adherence = try #require(result.adherence)
        #expect(adherence.duration == .withinTarget)
        #expect(adherence.effort == .aboveTarget)
        #expect(adherence.overall == .aboveTarget)
    }

    @Test("A skipped session is reported as skipped")
    func skipped() throws {
        let result = interpret(evidence(reportedRPE: 5, completion: .skipped))
        #expect(try #require(result.adherence).overall == .skipped)
    }

    @Test("A session still to come has no adherence verdict")
    func notYetDue() {
        #expect(interpret(evidence(completion: .notYetDue)).adherence == nil)
    }

    // MARK: - Aggregation input

    @Test("The aggregation session carries the interpreted values")
    func sessionMirrorsInterpretation() throws {
        let item = evidence(samples: readings([100, 105, 100, 102]), reportedRPE: 3)
        let result = interpret(item)
        let session = WorkoutIntelligence.session(from: item, interpretation: result)

        #expect(session.intensity == result.intensity.value?.intensity)
        #expect(session.load == result.load.value)
        #expect(session.sport == item.sport)
        #expect(session.date == item.date)
    }
}

@Suite("Adherence signals")
struct AdherenceSignalsTests {

    private let monday = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("Signals count above-target execution")
    func aboveTargetCounted() {
        let signals = AdherenceSignals(outcomes: [.withinTarget, .aboveTarget, .aboveTarget, .skipped])
        #expect(signals.aboveTargetCount == 2)
        #expect(signals.count(of: .skipped) == 1)
        #expect(signals.completedCount == 3)
    }

    @Test("Builder passes adherence through to the signals")
    func builderPopulatesAdherence() {
        let signals = TrainingSignalsBuilder.build(
            weeks: [PlanWeekSessions(weekNumber: 1, startDate: monday, sessions: [])],
            adherence: [.aboveTarget, .withinTarget],
            recovery: [:],
            asOf: monday
        )
        // The stub this replaces always produced an empty list, which silently
        // disabled one of the shadow evaluator's three concern sources.
        #expect(!signals.adherence.isEmpty)
        #expect(signals.adherence.aboveTargetCount == 1)
    }

    @Test("Above-target execution reaches the shadow evaluator")
    func adherenceReachesShadow() {
        let signals = TrainingSignalsBuilder.build(
            weeks: [PlanWeekSessions(weekNumber: 1, startDate: monday, sessions: [])],
            adherence: [.aboveTarget, .aboveTarget],
            recovery: [:],
            asOf: monday
        )
        let observation = ShadowEvaluator.evaluate(signals: signals, engineDecision: "progress")
        #expect(observation.reasons.contains { $0.contains("above target") })
    }
}
