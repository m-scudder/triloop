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

@MainActor
@Suite("Generated plan adherence")
struct GeneratedPlanAdherenceTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)
    private let builder = TrainingIntelligenceBuilder(birthDate: nil, observedMaximumHeartRate: nil)

    private func plan(origins: [WorkoutOrigin]) -> WeeklyPlan {
        WeeklyPlan(
            weekNumber: 1,
            startDate: start,
            endDate: start.addingTimeInterval(6 * 86_400),
            workouts: origins.enumerated().map { offset, origin in
                PlannedWorkout(
                    date: start.addingTimeInterval(Double(offset) * 86_400),
                    discipline: .running,
                    title: "Run",
                    targetRPE: RPERange(3, 4),
                    prescribedDurationSeconds: 1_800,
                    origin: origin
                )
            }
        )
    }

    @Test("Progress keeps all activity but counts only generated adherence", arguments: [WorkoutOrigin.custom, .library, .imported])
    func mixedOrigins(origin: WorkoutOrigin) async throws {
        let week = plan(origins: Array(repeating: .generated, count: 5) + [origin, origin])
        let workouts = week.orderedWorkouts
        for workout in Array(workouts.prefix(3)) + Array(workouts.suffix(2)) {
            workout.recordCompletion(with: FeedbackDraft())
        }
        let interpreted = builder.interpret(await builder.evidence(in: [week], provider: nil))
        let weeks = builder.weeks(from: [week], interpreted: interpreted)

        #expect(builder.adherenceShare(in: [week]) == 0.6)
        #expect(builder.plannedSessions(in: [week]).count == 5)
        #expect(interpreted.count == 5)
        #expect(interpreted.filter { $0.evidence.origin == origin }.count == 2)
        #expect(interpreted.allSatisfy { $0.interpretation.load.value != nil })
        #expect(interpreted.allSatisfy { $0.interpretation.intensity.value != nil })
        #expect(builder.adherence(from: interpreted, in: [week]).count == 5)
        #expect(try #require(weeks.first).sessions.count == 5)
        #expect(interpreted.compactMap { $0.session.durationSeconds }.reduce(0, +) == 9_000)

        let signals = TrainingSignalsBuilder.build(
            weeks: weeks,
            adherence: builder.adherence(from: interpreted, in: [week]),
            recovery: [:],
            asOf: week.endDate
        )
        #expect(signals.adherence.completedCount == 3)
    }

    @Test("Manual-only weeks have activity but no plan adherence", arguments: [WorkoutOrigin.custom, .library, .imported])
    func manualOnly(origin: WorkoutOrigin) async {
        let week = plan(origins: [origin, origin])
        for workout in week.trainingSessions {
            workout.recordCompletion(with: FeedbackDraft())
        }
        let interpreted = builder.interpret(await builder.evidence(in: [week], provider: nil))

        #expect(builder.adherenceShare(in: [week]) == nil)
        #expect(builder.adherenceShare(in: []) == nil)
        #expect(builder.plannedSessions(in: [week]).isEmpty)
        #expect(builder.adherence(from: interpreted, in: [week]).isEmpty)
        #expect(interpreted.count == 2)
        #expect(interpreted.allSatisfy { $0.interpretation.adherence == nil })
        #expect(interpreted.allSatisfy { $0.interpretation.load.value != nil })
        #expect(interpreted.allSatisfy { $0.interpretation.intensity.value != nil })
    }

    @Test("Skipped prescriptions reduce adherence while completed sessions need no report to count")
    func unresolvedPrescriptionsRemain() {
        let week = plan(origins: [.generated, .generated, .generated, .custom, .library])
        let workouts = week.orderedWorkouts
        workouts[0].recordCompletion(with: FeedbackDraft())
        workouts[1].skip()
        workouts[2].status = .completed
        workouts[3].recordCompletion(with: FeedbackDraft())
        workouts[4].skip()

        #expect(builder.adherenceShare(in: [week]) == 2.0 / 3.0)
        #expect(week.adherenceShare == 2.0 / 3.0)
        #expect(builder.plannedSessions(in: [week]).count == 3)
    }

    @Test("A generated session fulfilled by imported data still counts as prescribed")
    func generatedWithImportedExecution() throws {
        let week = plan(origins: [.generated])
        let workout = try #require(week.trainingSessions.first)
        workout.attach(ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            duration: 1_800
        ))
        #expect(builder.adherenceShare(in: [week]) == 1)
        #expect(week.adherenceShare == 1)
        #expect(workout.awaitingFeedback)
        #expect(WeeklyAnalyser().analyse(week).completedSessions == 0)
        workout.recordCompletion(with: FeedbackDraft())
        let evidence = try #require(builder.evidence(from: workout, samples: []))
        let interpreted = builder.interpret([evidence])

        #expect(evidence.origin.isPrescribedByTriLoop)
        #expect(builder.adherenceShare(in: [week]) == 1)
        #expect(builder.adherence(from: interpreted, in: [week]) == [.withinTarget])
    }

    @Test("Three of five is 60 percent and prescribed missed/skipped outcomes reach signals")
    func missedAndSkippedReachSignals() async {
        let week = plan(origins: Array(repeating: .generated, count: 5) + [.custom, .library, .imported])
        let workouts = week.orderedWorkouts
        workouts.prefix(3).forEach { $0.recordCompletion(with: FeedbackDraft()) }
        workouts[3].skip()
        workouts[5].skip()
        workouts[7].skip()
        let interpreted = builder.interpret(await builder.evidence(in: [week], provider: nil))
        let weeks = builder.weeks(from: [week], interpreted: interpreted)
        let signals = TrainingSignalsBuilder.build(
            weeks: weeks,
            adherence: builder.adherence(from: interpreted, in: [week]),
            recovery: [:],
            asOf: week.endDate
        )

        #expect(week.adherenceShare == 0.6)
        #expect(builder.adherenceShare(in: [week]) == 0.6)
        #expect(signals.adherence.completedCount == 3)
        #expect(signals.adherence.count(of: .missed) == 1)
        #expect(signals.adherence.count(of: .skipped) == 1)
        #expect(signals.adherence.outcomes.count == 5)
        #expect(weeks.flatMap(\.sessions).count == 3)
        #expect(weeks.flatMap(\.sessions).compactMap(\.durationSeconds).reduce(0, +) == 5_400)
    }

    @Test("Origin affects adherence, not load or intensity", arguments: [WorkoutOrigin.custom, .library, .imported])
    func interpretationEligibilityOnly(origin: WorkoutOrigin) {
        func evidence(origin: WorkoutOrigin) -> WorkoutEvidence {
            WorkoutEvidence(
                date: start,
                sport: .running,
                origin: origin,
                durationSeconds: 1_800,
                effort: EffortEvidence(reportedRPE: 8),
                plannedDurationSeconds: 1_800,
                targetRPE: RPERange(3, 4)
            )
        }
        let generated = WorkoutIntelligence.interpret(evidence(origin: .generated), maximumHeartRate: nil)
        let manual = WorkoutIntelligence.interpret(evidence(origin: origin), maximumHeartRate: nil)

        #expect(generated.adherence?.overall == .aboveTarget)
        #expect(manual.adherence == nil)
        #expect(manual.load.value != nil)
        #expect(manual.load == generated.load)
        #expect(manual.intensity == generated.intensity)
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
