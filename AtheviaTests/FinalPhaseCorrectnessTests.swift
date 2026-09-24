import Foundation
import Testing

@testable import Athevia

@Suite("Final phase correctness")
struct FinalPhaseCorrectnessTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    private func eventSetup(
        sport: EventSport,
        distance: EventDistance,
        baseline: AthleteBaseline = AthleteBaseline(),
        eventOffset: Int = 56
    ) -> AthleteSetup {
        AthleteSetup(
            objective: .event(
                sport: sport,
                distance: distance,
                eventDate: day(eventOffset)
            ),
            baseline: baseline,
            schedule: .everyDay(),
            preferences: sport.requiredTrainingSports.map {
                SportPreference(sport: $0, sessionsPerWeek: 2)
            },
            stage: .complete,
            completedAt: day(-30)
        )
    }

    private func summary(
        sport: Sport,
        on date: Date,
        duration: TimeInterval,
        distance: Double? = nil,
        continuousSwim: Double? = nil,
        metrics: RecordedMetrics? = nil
    ) -> ImportedWorkoutSummary {
        ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: sport,
            startDate: date,
            endDate: date.addingTimeInterval(duration),
            duration: duration,
            distanceMeters: distance,
            longestContinuousSwimMeters: continuousSwim,
            metrics: metrics,
            source: "Test"
        )
    }

    private func completed(
        sport: Discipline,
        on date: Date,
        title: String? = nil,
        summary: ImportedWorkoutSummary? = nil,
        feedback: FeedbackDraft = FeedbackDraft(rpe: 4, painScore: 0)
    ) -> PlannedWorkout {
        let workout = PlannedWorkout(
            date: date,
            discipline: sport,
            title: title ?? sport.displayName
        )
        if let summary {
            workout.attach(summary)
        }
        workout.recordCompletion(with: feedback, at: date.addingTimeInterval(3_600))
        return workout
    }

    private func plan(
        _ workouts: [PlannedWorkout],
        parameters: TrainingParameters = TrainingParameters()
    ) -> WeeklyPlan {
        WeeklyPlan(
            weekNumber: 8,
            startDate: day(-6),
            endDate: now,
            status: .active,
            parameters: parameters,
            workouts: workouts
        )
    }

    @Test("Run walk baseline is superseded by demonstrated 5K")
    func progressedRunnerSupersedesBaseline() {
        let setup = eventSetup(
            sport: .running,
            distance: EventDistance(kind: .run10K),
            baseline: AthleteBaseline(running: .runWalk)
        )
        let run = completed(
            sport: .running,
            on: day(-2),
            summary: summary(
                sport: .running,
                on: day(-2),
                duration: 30 * 60,
                distance: 5_400
            )
        )
        let history = plan([run])

        let capability = AthleteCapabilityAssessmentBuilder(calendar: calendar)
            .build(setup: setup, plans: [history], asOf: now)
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, capability: capability, asOf: now)

        #expect(capability.running.longestRecordedDistanceMeters >= 5_000)
        #expect(capability.running.hasContinuousCapability)
        #expect(journey.primaryFocus?.kind != .runWalkContinuity)
    }

    @Test("750m swim total never becomes 750m continuous")
    func swimVolumeDoesNotInventContinuity() {
        let setup = eventSetup(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            baseline: AthleteBaseline(
                running: .regular5K,
                swimming: .continuous100,
                cycling: .sixtyPlus
            )
        )
        let swim = completed(
            sport: .swimming,
            on: day(-1),
            summary: summary(
                sport: .swimming,
                on: day(-1),
                duration: 35 * 60,
                distance: 750,
                continuousSwim: 100
            )
        )
        let history = plan([swim])

        let capability = AthleteCapabilityAssessmentBuilder(calendar: calendar)
            .build(setup: setup, plans: [history], asOf: now)
        let snapshot = JourneyProgressBuilder(calendar: calendar)
            .build(setup: setup, plans: [history], asOf: now)
        let swimCapability = snapshot.capabilities.first { $0.sport == .swimming }

        #expect(capability.swimming.longestRecordedTotalWorkoutMeters == 750)
        #expect(capability.swimming.longestProvenContinuousMeters == 100)
        #expect(swimCapability?.currentEvidence.contains("100 m continuous demonstrated") == true)
        #expect(swimCapability?.state != .demonstrated)
    }

    @Test("Imported swim without continuity remains unverified")
    func importedSwimWithoutContinuityIsUnverified() {
        let setup = eventSetup(
            sport: .swimming,
            distance: EventDistance(kind: .swimming500M),
            baseline: AthleteBaseline(swimming: .none)
        )
        let swim = completed(
            sport: .swimming,
            on: day(-1),
            summary: summary(
                sport: .swimming,
                on: day(-1),
                duration: 30 * 60,
                distance: 800,
                continuousSwim: nil
            )
        )
        let snapshot = JourneyProgressBuilder(calendar: calendar)
            .build(setup: setup, plans: [plan([swim])], asOf: now)

        #expect(snapshot.capabilities.first?.currentEvidence.contains("Continuous distance not verified") == true)
        #expect(snapshot.capabilities.first?.state == .developing)
    }

    @Test("No completed evidence yields not enough data")
    func readinessNeedsEvidence() {
        let setup = eventSetup(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            baseline: AthleteBaseline(running: .regular5K)
        )
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, plans: [], asOf: now)

        #expect(journey.readiness.status == .notEnoughData)
    }

    @Test("Baseline alone never yields event ready")
    func baselineCannotProduceEventReady() {
        let setup = eventSetup(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            baseline: AthleteBaseline(
                running: .regular5K,
                swimming: .continuous200Plus,
                cycling: .sixtyPlus
            )
        )
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, plans: [], asOf: now)

        #expect(journey.readiness.status != .eventReady)
    }

    @Test("Recovery problem takes readiness to needs attention")
    func recoveryOverridesReadiness() {
        let setup = eventSetup(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            baseline: AthleteBaseline(running: .regular5K),
            eventOffset: 14
        )
        let run = completed(
            sport: .running,
            on: day(-1),
            summary: summary(
                sport: .running,
                on: day(-1),
                duration: 30 * 60,
                distance: 5_000
            ),
            feedback: FeedbackDraft(rpe: 7, painScore: 6, recoveryFeeling: .tired)
        )
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, plans: [plan([run])], asOf: now)

        #expect(journey.readiness.status == .needsAttention)
    }

    @Test("Strong triathlon evidence can conservatively reach event ready")
    func demonstratedSprintCanBeEventReady() {
        var setup = eventSetup(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            baseline: AthleteBaseline(
                running: .runWalk,
                swimming: .continuous25,
                cycling: .twentyToThirty
            ),
            eventOffset: 28
        )

        let run = completed(
            sport: .running,
            on: day(-6),
            summary: summary(
                sport: .running,
                on: day(-6),
                duration: 31 * 60,
                distance: 5_200
            )
        )
        let swim = completed(
            sport: .swimming,
            on: day(-5),
            summary: summary(
                sport: .swimming,
                on: day(-5),
                duration: 35 * 60,
                distance: 900,
                continuousSwim: 800
            )
        )
        let bike = completed(
            sport: .cycling,
            on: day(-4),
            summary: summary(
                sport: .cycling,
                on: day(-4),
                duration: 70 * 60,
                distance: 25_000
            )
        )
        let brickMetrics = RecordedMetrics(
            multisportSegments: [
                .init(sport: .cycling, durationSeconds: 45 * 60, distanceMeters: 20_000),
                .init(sport: nil, isTransition: true, durationSeconds: 180),
                .init(sport: .running, durationSeconds: 18 * 60, distanceMeters: 3_000)
            ]
        )
        let brick = completed(
            sport: .multisport,
            on: day(-2),
            title: "Bike + Run Brick",
            summary: summary(
                sport: .cycling,
                on: day(-2),
                duration: 66 * 60,
                metrics: brickMetrics
            )
        )

        let history = plan([run, swim, bike, brick])
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, plans: [history], asOf: now)

        #expect(journey.readiness.status == .eventReady)
        #expect(journey.sportPriorities.first?.sport != .swimming)
    }

    @Test("Pain blocks open water prescription even with consent")
    func recoveryBlocksOpenWater() {
        let setup = eventSetup(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            baseline: AthleteBaseline(swimming: .continuous200Plus),
            eventOffset: 28
        )
        let swim = completed(
            sport: .swimming,
            on: day(-1),
            summary: summary(
                sport: .swimming,
                on: day(-1),
                duration: 35 * 60,
                distance: 800,
                continuousSwim: 800
            ),
            feedback: FeedbackDraft(rpe: 4, painScore: 6)
        )
        let capability = AthleteCapabilityAssessmentBuilder(calendar: calendar)
            .build(setup: setup, plans: [plan([swim])], asOf: now)
        let builder = PhaseWorkoutPrescriptionBuilder()
        let journey = TrainingJourney(
            phase: .specific,
            weeksRemaining: 4,
            readiness: .init(status: .needsAttention, sports: []),
            weeklyObjectives: [],
            sportPriorities: []
        )
        let workout = builder.workout(
            sport: .swimming,
            on: now,
            parameters: TrainingParameters(),
            journey: journey,
            objective: setup.objective,
            capability: capability,
            openWaterConsent: .init(
                explicitlyConfirmed: true,
                hasSafeVenue: true,
                hasSupervisionOrBuddy: true
            )
        )

        #expect(workout.title != "Open-Water Preparation")
    }

    @Test("Open water requires every explicit consent flag")
    func openWaterConsentIsStrict() {
        #expect(!OpenWaterTrainingConsent.unavailable.permitsPrescription)
        #expect(!OpenWaterTrainingConsent(
            explicitlyConfirmed: true,
            hasSafeVenue: false,
            hasSupervisionOrBuddy: true
        ).permitsPrescription)
        #expect(!OpenWaterTrainingConsent(
            explicitlyConfirmed: true,
            hasSafeVenue: true,
            hasSupervisionOrBuddy: false
        ).permitsPrescription)
        #expect(OpenWaterTrainingConsent(
            explicitlyConfirmed: true,
            hasSafeVenue: true,
            hasSupervisionOrBuddy: true
        ).permitsPrescription)
    }

    @Test("Brick preserves explicit bike transition run semantics")
    func brickSegmentsAreExplicit() {
        let workout = MultisportPrescribedSessions.brick(
            on: now,
            parameters: TrainingParameters(),
            prescription: MultisportTrainingPolicy().brick(parameters: TrainingParameters())
        )

        #expect(workout.discipline == .multisport)
        #expect(workout.orderedSteps.map(\.kind) == [
            .cyclingSegment,
            .cyclingSegment,
            .transition,
            .runningSegment,
            .runningSegment
        ])
    }

    @Test("Multisport run segment does not inflate cycling capability")
    func segmentEvidenceDoesNotCrossSports() {
        let setup = eventSetup(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint)
        )
        let metrics = RecordedMetrics(multisportSegments: [
            .init(sport: .cycling, durationSeconds: 40 * 60, distanceMeters: 18_000),
            .init(sport: nil, isTransition: true, durationSeconds: 180),
            .init(sport: .running, durationSeconds: 25 * 60, distanceMeters: 5_000)
        ])
        let brick = completed(
            sport: .multisport,
            on: day(-1),
            title: "Bike + Run Brick",
            summary: summary(
                sport: .cycling,
                on: day(-1),
                duration: 68 * 60,
                distance: nil,
                metrics: metrics
            )
        )
        let capability = AthleteCapabilityAssessmentBuilder(calendar: calendar)
            .build(setup: setup, plans: [plan([brick])], asOf: now)

        #expect(capability.cycling.longestRecordedDistanceMeters == 18_000)
        #expect(capability.running.longestRecordedDistanceMeters == 5_000)
    }

    @Test("Passing event date alone never marks event complete")
    func datePassageDoesNotCompleteEvent() {
        var setup = eventSetup(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventOffset: -1
        )

        #expect(setup.eventState.status == .upcoming)
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, plans: [], asOf: now)
        #expect(journey.eventResolutionRequired)
        #expect(setup.eventState.status == .upcoming)
    }

    @Test("Completed event recovery has a deterministic end")
    func postEventRecoveryEnds() {
        var setup = eventSetup(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventOffset: -2
        )
        setup.eventState = AthleteEventState(
            status: .completed,
            resolvedAt: day(-2),
            completionEvidence: .athleteConfirmation
        )
        let planner = TrainingJourneyPlanner(calendar: calendar)

        let during = planner.plan(setup: setup, plans: [], asOf: now)
        let after = planner.plan(setup: setup, plans: [], asOf: day(3))

        #expect(during.phase == .recovery)
        #expect(after.phase != .recovery)
        #expect(after.requiresNextObjective)
    }

    @Test("Missed and cancelled events never receive completion milestone")
    func unresolvedEventsDoNotAwardCompletion() {
        var missed = eventSetup(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventOffset: -1
        )
        missed.eventState = AthleteEventState(status: .missed, resolvedAt: now)

        var cancelled = missed
        cancelled.eventState = AthleteEventState(status: .cancelled, resolvedAt: now)

        let builder = JourneyProgressBuilder(calendar: calendar)
        #expect(!builder.milestones(setup: missed, plans: [], asOf: now).contains {
            $0.kind == .eventCompleted
        })
        #expect(!builder.milestones(setup: cancelled, plans: [], asOf: now).contains {
            $0.kind == .eventCompleted
        })
    }

    @Test("Swim total distance cannot create continuous milestone")
    func swimTotalCannotCreateContinuousMilestone() {
        let setup = eventSetup(
            sport: .swimming,
            distance: EventDistance(kind: .swimming1K)
        )
        let swim = completed(
            sport: .swimming,
            on: day(-1),
            summary: summary(
                sport: .swimming,
                on: day(-1),
                duration: 40 * 60,
                distance: 1_000,
                continuousSwim: 100
            )
        )
        let milestones = JourneyProgressBuilder(calendar: calendar)
            .milestones(setup: setup, plans: [plan([swim])], asOf: now)

        #expect(milestones.contains { $0.kind == .longestTotalSwimWorkout })
        #expect(!milestones.contains { $0.kind == .swim1KContinuous })
    }

    @Test("Confirmed event completion awards event milestone once")
    func confirmedEventMilestoneIsIdempotent() {
        var setup = eventSetup(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventOffset: -1
        )
        setup.eventState = AthleteEventState(
            status: .completed,
            resolvedAt: day(-1),
            completionEvidence: .athleteConfirmation
        )
        let builder = JourneyProgressBuilder(calendar: calendar)
        let milestones = builder.milestones(setup: setup, plans: [], asOf: now)

        #expect(milestones.filter { $0.kind == .eventCompleted }.count == 1)
    }

    @Test("General fitness journey has no event capability rows")
    func generalFitnessHasNoEventReadiness() {
        let setup = AthleteSetup(
            objective: .init(kind: .generalFitness),
            baseline: AthleteBaseline(running: .runWalk),
            schedule: .everyDay(),
            preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)]
        )
        let snapshot = JourneyProgressBuilder(calendar: calendar)
            .build(setup: setup, plans: [], asOf: now)

        #expect(snapshot.capabilities.isEmpty)
        #expect(snapshot.journey.readiness.sports.isEmpty)
    }
    @Test("Every phase selects appropriate run swim cycle and triathlon semantics")
    func phaseMatrixIsOperational() {
        let builder = PhaseWorkoutPrescriptionBuilder()
        let parameters = TrainingParameters(
            runIsContinuous: true,
            runContinuousSeconds: 30 * 60,
            swimRepeatDistanceMeters: 200,
            swimRepeatCount: 4,
            swimRestSeconds: 30,
            swimPoolLengthMeters: 25,
            rideWorkSeconds: 60 * 60
        )
        let triObjective = TrainingObjective.event(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            eventDate: day(35)
        )

        for phase in TrainingPhase.allCases {
            let journey = TrainingJourney(
                phase: phase,
                weeksRemaining: phase == .raceWeek ? 1 : 5,
                readiness: .init(status: .building, sports: []),
                weeklyObjectives: [],
                sportPriorities: [
                    .init(sport: .swimming, rank: 1, reason: "Test"),
                    .init(sport: .cycling, rank: 2, reason: "Test"),
                    .init(sport: .running, rank: 3, reason: "Test")
                ]
            )

            let run = builder.workout(
                sport: .running,
                on: now,
                parameters: parameters,
                journey: journey,
                objective: triObjective,
                capability: nil,
                sportOrdinal: 2
            )
            let swim = builder.workout(
                sport: .swimming,
                on: now,
                parameters: parameters,
                journey: journey,
                objective: triObjective,
                capability: nil,
                sportOrdinal: 1
            )
            let cycle = builder.workout(
                sport: .cycling,
                on: now,
                parameters: parameters,
                journey: journey,
                objective: triObjective,
                capability: nil,
                sportOrdinal: 0
            )

            if phase == .recovery {
                #expect(run.discipline == .recovery)
                #expect(swim.discipline == .recovery)
                #expect(cycle.discipline == .recovery)
            } else {
                #expect(run.discipline == .running)
                #expect(swim.discipline == .swimming)
                #expect(cycle.discipline == .cycling)
            }

            switch phase {
            case .foundation:
                #expect(run.title == "Easy Continuous Run")
                #expect(swim.title == "Endurance Swim")
                #expect(cycle.title == "Easy Ride")
            case .build:
                #expect(run.title == "Easy Run")
                #expect(swim.title == "Endurance Swim")
                #expect(cycle.title == "Easy Ride")
            case .specific:
                #expect(run.title == "Race-Specific Steady Run")
                #expect(swim.title == "Race-Distance Preparation")
                #expect(cycle.title == "Race-Specific Steady Ride")
            case .taper:
                #expect(run.title == "Easy Run")
                #expect(swim.title == "Easy Technique Swim")
                #expect(cycle.title == "Easy Ride")
            case .raceWeek:
                #expect(run.title == "Race-Week Easy Run")
                #expect(swim.title == "Race-Week Easy Swim")
                #expect(cycle.title == "Race-Week Easy Ride")
            case .recovery:
                break
            }

            let triPolicy = MultisportTrainingPolicy()
            if phase == .specific {
                #expect(triPolicy.canScheduleBrick(
                    journey: journey,
                    objective: triObjective,
                    schedule: .everyDay(),
                    recoveringSports: []
                ))
            } else {
                #expect(!triPolicy.canScheduleBrick(
                    journey: journey,
                    objective: triObjective,
                    schedule: .everyDay(),
                    recoveringSports: []
                ))
            }
        }
    }

    @Test("Performance intent modestly changes only supported specific work")
    func performanceIntentDoesNotBypassCapability() {
        let builder = PhaseWorkoutPrescriptionBuilder()
        let journey = TrainingJourney(
            phase: .specific,
            weeksRemaining: 4,
            readiness: .init(status: .building, sports: []),
            weeklyObjectives: [],
            sportPriorities: []
        )
        let parameters = TrainingParameters(
            runIsContinuous: true,
            runContinuousSeconds: 35 * 60
        )
        let performance = TrainingObjective.event(
            sport: .running,
            distance: EventDistance(kind: .run10K),
            eventDate: day(28),
            targetIntent: .performance
        )

        let unsupported = builder.workout(
            sport: .running,
            on: now,
            parameters: parameters,
            journey: journey,
            objective: performance,
            capability: nil,
            sportOrdinal: 2
        )
        let unsupportedWork = unsupported.orderedSteps.first { $0.kind == .work }
        #expect(unsupportedWork?.targetIntensity != .hard)
    }


}
