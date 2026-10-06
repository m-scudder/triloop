import Foundation
import Testing

@testable import Athevia

@Suite("Training parameters")
struct TrainingParametersTests {

    @Test("Week one defaults match the seeded week")
    func defaultsMatchWeekOne() {
        let parameters = TrainingParameters()

        #expect(parameters.runIntervalSeconds == 60)
        #expect(parameters.runRepeatCount == 6)
        #expect(parameters.swimTotalMeters == 300)
        #expect(parameters.swimRestSeconds == 45)
        #expect(parameters.rideWorkSeconds == TimeInterval(20 * 60))
    }

    @Test("Progression moves only its own variable")
    func progressionIsSingleVariable() {
        let base = TrainingParameters()
        let next = base.applying(.runIntervalDuration(deltaSeconds: 15), to: .running)

        #expect(next.runIntervalSeconds == 75)
        #expect(next.runRepeatCount == base.runRepeatCount)
        #expect(next.runWalkSeconds == base.runWalkSeconds)
        #expect(next.rideWorkSeconds == base.rideWorkSeconds)
        #expect(next.swimTotalMeters == base.swimTotalMeters)
    }

    @Test("Holding changes nothing")
    func holdIsANoOp() {
        let base = TrainingParameters()

        #expect(base.applying(.hold, to: .running) == base)
        #expect(base.applying(.substituteRecovery, to: .cycling) == base)
    }

    @Test("Each sport reduces volume with its own variable")
    func reductionUsesTheRightVariable() {
        let base = TrainingParameters()

        let run = base.applying(.reduceVolume(fraction: 0.2), to: .running)
        let swim = base.applying(.reduceVolume(fraction: 0.2), to: .swimming)
        let ride = base.applying(.reduceVolume(fraction: 0.2), to: .cycling)

        #expect(run.runRepeatCount == 5)
        #expect(run.runIntervalSeconds == base.runIntervalSeconds)
        #expect(swim.swimTotalMeters == 250)
        #expect(ride.rideWorkSeconds == TimeInterval(15 * 60))
    }

    @Test("Swim volume stays in whole lengths")
    func swimVolumeRoundsToLengths() {
        let parameters = TrainingParameters().applying(.reduceVolume(fraction: 0.1), to: .swimming)

        #expect(parameters.swimTotalMeters.truncatingRemainder(dividingBy: 25) == 0)
    }

    @Test("Repeated reductions stop at a floor")
    func reductionsRespectFloors() {
        var parameters = TrainingParameters()
        for _ in 0..<20 {
            parameters = parameters.applying(.reduceVolume(fraction: 0.5), to: .running)
            parameters = parameters.applying(.reduceVolume(fraction: 0.5), to: .swimming)
            parameters = parameters.applying(.reduceVolume(fraction: 0.5), to: .cycling)
        }

        #expect(parameters.runRepeatCount == TrainingParameters.Limits.minimumRunRepeatCount)
        #expect(parameters.swimTotalMeters == TrainingParameters.Limits.minimumSwimMeters)
        #expect(parameters.rideWorkSeconds == TrainingParameters.Limits.minimumRideWorkSeconds)
    }

    @Test("A larger availability window never manufactures extra cycling load")
    func largerWindowDoesNotInflateCycling() {
        let parameters = TrainingParameters().fillingTrainingWindow(minutes: 60)
        #expect(parameters.rideWorkSeconds == 20 * 60)
        #expect(
            parameters.rideWarmUpSeconds
                + parameters.rideWorkSeconds
                + parameters.rideCooldownSeconds == 30 * 60
        )
    }

    @Test("Training window cap never exceeds selected time")
    func cappedWindowStaysInsideAvailability() {
        let parameters = TrainingParameters().fillingTrainingWindow(minutes: 30)
        #expect(
            parameters.rideWarmUpSeconds
                + parameters.rideWorkSeconds
                + parameters.rideCooldownSeconds <= 30 * 60
        )
    }


    @Test("Continuous endurance durations normalize to five minute blocks")
    func enduranceDurationsUseFiveMinuteBlocks() {
        var parameters = TrainingParameters()
        parameters.runIsContinuous = true
        parameters.runContinuousSeconds = 30 * 60

        let taperedRun = parameters.applying(.reduceVolume(fraction: 0.2), to: .running)
        let taperedRide = parameters.applying(.reduceVolume(fraction: 0.2), to: .cycling)

        #expect(taperedRun.runContinuousSeconds == 25 * 60)
        #expect(taperedRide.rideWorkSeconds == 15 * 60)
        #expect(taperedRun.runContinuousSeconds.truncatingRemainder(dividingBy: 5 * 60) == 0)
        #expect(taperedRide.rideWorkSeconds.truncatingRemainder(dividingBy: 5 * 60) == 0)
    }

}


@Suite("Onboarding prescription matrix")
struct OnboardingPrescriptionMatrixTests {
    private let timeOptions = [30, 45, 60, 90, 120]
    private let dayTargets = [2, 3, 4]
    private let nonEventGoals: [TrainingObjectiveKind] = [
        .generalFitness, .improveEndurance, .returnToTraining
    ]

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return value
    }

    private var startDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)) ?? .now
    }

    private func schedule(minutes: Int) -> AthleteSchedule {
        .everyDay(maxDurationMinutes: minutes)
    }

    private func setup(
        sport: Sport,
        baseline: AthleteBaseline,
        objective: TrainingObjective,
        targetDays: Int,
        minutes: Int
    ) -> AthleteSetup {
        AthleteSetup(
            objective: objective,
            trainingDayTarget: targetDays,
            baseline: baseline,
            schedule: schedule(minutes: minutes),
            preferences: [SportPreference(sport: sport, sessionsPerWeek: 1)],
            stage: .complete,
            completedAt: startDate
        )
    }

    private func build(
        sport: Sport,
        baseline: AthleteBaseline,
        objective: TrainingObjective,
        targetDays: Int,
        minutes: Int,
        poolLengthMeters: Double = 25
    ) throws -> WeeklyPlan {
        try FirstWeekBuilder(calendar: calendar).build(
            setup: setup(
                sport: sport,
                baseline: baseline,
                objective: objective,
                targetDays: targetDays,
                minutes: minutes
            ),
            poolLengthMeters: poolLengthMeters,
            startDate: startDate
        )
    }

    private func expectedOpeningDays(_ requested: Int) -> Int {
        requested == 4 ? 3 : requested
    }

    private func stepSignature(_ step: WorkoutStep) -> String {
        let children = step.orderedChildren.map(stepSignature).joined(separator: "|")
        return [
            step.kind.rawValue,
            step.title,
            step.durationSeconds.map { String($0) } ?? "-",
            step.distanceMeters.map { String($0) } ?? "-",
            step.repeatCount.map { String($0) } ?? "-",
            step.targetIntensity?.rawValue ?? "-",
            children
        ].joined(separator: ":")
    }

    private func signature(_ workout: PlannedWorkout) -> String {
        [
            workout.title,
            workout.goal,
            workout.estimatedDurationSeconds.map { String($0) } ?? "-",
            workout.estimatedDistanceMeters.map { String($0) } ?? "-",
            workout.orderedSteps.map(stepSignature).joined(separator: "/")
        ].joined(separator: "#")
    }

    private func assertWholeSeconds(_ step: WorkoutStep) {
        if let duration = step.durationSeconds {
            #expect(duration == duration.rounded())
        }
        step.children.forEach(assertWholeSeconds)
    }

    @Test("Every running onboarding combination respects capability and availability")
    func runningMatrix() throws {
        for running in RunningBaseline.allCases {
            for goal in nonEventGoals {
                for targetDays in dayTargets {
                    for minutes in timeOptions {
                        let baseline = AthleteBaseline(running: running)
                        let objective = TrainingObjective(kind: goal)
                        let plan = try build(
                            sport: .running,
                            baseline: baseline,
                            objective: objective,
                            targetDays: targetDays,
                            minutes: minutes
                        )

                        let runs = plan.trainingSessions.filter { $0.discipline == .running }
                        #expect(runs.count == expectedOpeningDays(targetDays))

                        let resolved = StartingParameterResolver()
                            .resolve(
                                baseline: baseline,
                                goal: objective.legacyGoal,
                                poolLengthMeters: 25
                            )
                            .capped(toTrainingMinutes: minutes)

                        for run in runs {
                            if let duration = run.estimatedDurationSeconds {
                                #expect(duration <= TimeInterval(minutes * 60))
                            }
                            run.steps.forEach(assertWholeSeconds)

                            let warmup = run.orderedSteps.first { $0.kind == .warmUp }
                            let cooldown = run.orderedSteps.first { $0.kind == .cooldown }
                            #expect(warmup?.durationSeconds == 5 * 60)
                            #expect(cooldown?.durationSeconds == 5 * 60)

                            if resolved.runIsContinuous {
                                let work = run.orderedSteps.first { $0.kind == .work }
                                let seconds = try #require(work?.durationSeconds)
                                #expect(seconds <= resolved.runContinuousSeconds)
                                #expect(seconds.truncatingRemainder(dividingBy: 5 * 60) == 0)
                            } else {
                                let repeats = run.orderedSteps.first { $0.kind == .repeatBlock }
                                #expect((repeats?.repeatCount ?? 0) <= resolved.runRepeatCount)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Every cycling onboarding combination respects capability and availability")
    func cyclingMatrix() throws {
        for cycling in CyclingBaseline.allCases {
            for goal in nonEventGoals {
                for targetDays in dayTargets {
                    for minutes in timeOptions {
                        let baseline = AthleteBaseline(cycling: cycling)
                        let objective = TrainingObjective(kind: goal)
                        let plan = try build(
                            sport: .cycling,
                            baseline: baseline,
                            objective: objective,
                            targetDays: targetDays,
                            minutes: minutes
                        )

                        let rides = plan.trainingSessions.filter { $0.discipline == .cycling }
                        #expect(rides.count == expectedOpeningDays(targetDays))

                        let resolved = StartingParameterResolver()
                            .resolve(
                                baseline: baseline,
                                goal: objective.legacyGoal,
                                poolLengthMeters: 25
                            )
                            .capped(toTrainingMinutes: minutes)

                        for ride in rides {
                            if let duration = ride.estimatedDurationSeconds {
                                #expect(duration <= TimeInterval(minutes * 60))
                            }
                            ride.steps.forEach(assertWholeSeconds)

                            let workDurations = ride.orderedSteps
                                .flatMap { step -> [TimeInterval] in
                                    if step.kind == .work, let duration = step.durationSeconds {
                                        return [duration]
                                    }
                                    return step.orderedChildren.compactMap {
                                        $0.kind == .work ? $0.durationSeconds : nil
                                    }
                                }
                            for seconds in workDurations where seconds >= 10 * 60 {
                                #expect(seconds <= resolved.rideWorkSeconds)
                                #expect(seconds.truncatingRemainder(dividingBy: 5 * 60) == 0)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Every swimming baseline, goal and frequency combination stays capability-derived")
    func swimmingMatrix() throws {
        for swimming in SwimmingBaseline.allCases {
            for goal in nonEventGoals {
                for targetDays in dayTargets {
                    for minutes in timeOptions {
                        let baseline = AthleteBaseline(swimming: swimming)
                        let plan = try build(
                            sport: .swimming,
                            baseline: baseline,
                            objective: TrainingObjective(kind: goal),
                            targetDays: targetDays,
                            minutes: minutes
                        )

                        let swims = plan.trainingSessions.filter { $0.discipline == .swimming }
                        #expect(swims.count == expectedOpeningDays(targetDays))

                        let resolved = StartingParameterResolver()
                            .resolve(
                                baseline: baseline,
                                goal: TrainingObjective(kind: goal).legacyGoal,
                                poolLengthMeters: 25
                            )
                            .capped(toTrainingMinutes: minutes)

                        for swim in swims {
                            swim.steps.forEach(assertWholeSeconds)
                            if let distance = swim.estimatedDistanceMeters {
                                #expect(distance > 0)
                                #expect(distance <= resolved.swimTotalMeters)
                                #expect(distance.truncatingRemainder(dividingBy: 25) == 0)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Running baselines create distinct first-week prescriptions")
    func runningBaselinesAreDistinct() throws {
        let signatures = try RunningBaseline.allCases.map { running in
            let plan = try build(
                sport: .running,
                baseline: AthleteBaseline(running: running),
                objective: TrainingObjective(kind: .improveEndurance),
                targetDays: 2,
                minutes: 120
            )
            return signature(try #require(plan.trainingSessions.first))
        }

        #expect(Set(signatures).count == RunningBaseline.allCases.count)
    }

    @Test("Cycling baselines create distinct first-week prescriptions")
    func cyclingBaselinesAreDistinct() throws {
        let signatures = try CyclingBaseline.allCases.map { cycling in
            let plan = try build(
                sport: .cycling,
                baseline: AthleteBaseline(cycling: cycling),
                objective: TrainingObjective(kind: .improveEndurance),
                targetDays: 2,
                minutes: 120
            )
            return signature(try #require(plan.trainingSessions.first))
        }

        #expect(Set(signatures).count == CyclingBaseline.allCases.count)
    }

    @Test("Swimming baselines create distinct first-week prescriptions")
    func swimmingBaselinesAreDistinct() throws {
        let signatures = try SwimmingBaseline.allCases.map { swimming in
            let plan = try build(
                sport: .swimming,
                baseline: AthleteBaseline(swimming: swimming),
                objective: TrainingObjective(kind: .improveEndurance),
                targetDays: 2,
                minutes: 120
            )
            return signature(try #require(plan.trainingSessions.first))
        }

        #expect(Set(signatures).count == SwimmingBaseline.allCases.count)
    }

    @Test("Non-event goals materially change each sport's prescription")
    func goalsAreDistinctPerSport() throws {
        let cases: [(Sport, AthleteBaseline)] = [
            (.running, AthleteBaseline(running: .regular5K)),
            (.cycling, AthleteBaseline(cycling: .fortyFiveToSixty)),
            (.swimming, AthleteBaseline(swimming: .continuous200Plus))
        ]

        for (sport, baseline) in cases {
            let signatures = try nonEventGoals.map { goal in
                let plan = try build(
                    sport: sport,
                    baseline: baseline,
                    objective: TrainingObjective(kind: goal),
                    targetDays: 3,
                    minutes: 60
                )
                return plan.trainingSessions
                    .filter { $0.discipline.sport == sport }
                    .map(signature)
                    .joined(separator: "||")
            }

            #expect(Set(signatures).count == nonEventGoals.count)
        }
    }

    @Test("Large time availability never inflates a ten minute runner")
    func tenMinuteRunnerIsNotInflatedByAvailability() throws {
        for minutes in timeOptions {
            let plan = try build(
                sport: .running,
                baseline: AthleteBaseline(running: .continuous10Minutes),
                objective: TrainingObjective(kind: .improveEndurance),
                targetDays: 2,
                minutes: minutes
            )
            for run in plan.trainingSessions where run.discipline == .running {
                let work = try #require(run.orderedSteps.first { $0.kind == .work })
                #expect(work.durationSeconds == 10 * 60)
            }
        }
    }

    @Test("Taper is applied exactly once and keeps five minute warmup and cooldown")
    func taperIsAppliedOnce() throws {
        let eventDate = calendar.date(byAdding: .day, value: 10, to: startDate)
        let objective = TrainingObjective.event(
            sport: .running,
            distance: EventDistance(kind: .run10K),
            eventDate: eventDate,
            targetIntent: .complete
        )
        let plan = try build(
            sport: .running,
            baseline: AthleteBaseline(running: .regular5K),
            objective: objective,
            targetDays: 3,
            minutes: 60
        )

        let run = try #require(plan.trainingSessions.first { $0.discipline == .running })
        let warmup = try #require(run.orderedSteps.first { $0.kind == .warmUp })
        let work = try #require(run.orderedSteps.first { $0.kind == .work })
        let cooldown = try #require(run.orderedSteps.first { $0.kind == .cooldown })

        #expect(warmup.durationSeconds == 5 * 60)
        #expect(work.durationSeconds == 25 * 60)
        #expect(cooldown.durationSeconds == 5 * 60)
        #expect(run.estimatedDurationSeconds == 35 * 60)
    }

    @Test("Swim stroke changes the generated prescription")
    func swimStrokeIsConsumed() throws {
        let freestyle = try build(
            sport: .swimming,
            baseline: AthleteBaseline(swimming: .continuous100, stroke: .freestyle),
            objective: TrainingObjective(kind: .improveEndurance),
            targetDays: 2,
            minutes: 45
        )
        let mixed = try build(
            sport: .swimming,
            baseline: AthleteBaseline(swimming: .continuous100, stroke: .mixed),
            objective: TrainingObjective(kind: .improveEndurance),
            targetDays: 2,
            minutes: 45
        )

        let freestyleWorkout = try #require(freestyle.trainingSessions.first)
        let mixedWorkout = try #require(mixed.trainingSessions.first)

        #expect(freestyle.parameters.swimStroke == .freestyle)
        #expect(mixed.parameters.swimStroke == .mixed)
        #expect(signature(freestyleWorkout) != signature(mixedWorkout))
    }

    @Test("Pool length changes valid swim geometry")
    func poolLengthIsConsumed() throws {
        let pools = [25.0, 33.3, 50.0]
        let signatures = try pools.map { pool in
            let plan = try build(
                sport: .swimming,
                baseline: AthleteBaseline(swimming: .continuous200Plus),
                objective: TrainingObjective(kind: .improveEndurance),
                targetDays: 2,
                minutes: 60,
                poolLengthMeters: pool
            )
            return signature(try #require(plan.trainingSessions.first))
        }

        #expect(Set(signatures).count == pools.count)
    }

    @Test("Every running event distance and intent builds a bounded prescription")
    func runningEventMatrix() throws {
        for kind in EventDistanceKind.choices(for: .running) {
            for intent in EventTargetIntent.allCases {
                for minutes in timeOptions {
                    let objective = TrainingObjective.event(
                        sport: .running,
                        distance: EventDistance(kind: kind),
                        eventDate: calendar.date(byAdding: .day, value: 28, to: startDate),
                        targetIntent: intent
                    )
                    let plan = try build(
                        sport: .running,
                        baseline: AthleteBaseline(running: .regular5K),
                        objective: objective,
                        targetDays: 3,
                        minutes: minutes
                    )

                    #expect(plan.trainingSessions.contains { $0.discipline == .running })
                    for workout in plan.trainingSessions where workout.discipline == .running {
                        if let duration = workout.estimatedDurationSeconds {
                            #expect(duration <= TimeInterval(minutes * 60))
                        }
                        workout.steps.forEach(assertWholeSeconds)
                    }
                }
            }
        }
    }

    @Test("Every cycling event distance and intent builds a bounded prescription")
    func cyclingEventMatrix() throws {
        for kind in EventDistanceKind.choices(for: .cycling) {
            for intent in EventTargetIntent.allCases {
                for minutes in timeOptions {
                    let objective = TrainingObjective.event(
                        sport: .cycling,
                        distance: EventDistance(kind: kind),
                        eventDate: calendar.date(byAdding: .day, value: 28, to: startDate),
                        targetIntent: intent
                    )
                    let plan = try build(
                        sport: .cycling,
                        baseline: AthleteBaseline(cycling: .sixtyPlus),
                        objective: objective,
                        targetDays: 3,
                        minutes: minutes
                    )

                    #expect(plan.trainingSessions.contains { $0.discipline == .cycling })
                    for workout in plan.trainingSessions where workout.discipline == .cycling {
                        if let duration = workout.estimatedDurationSeconds {
                            #expect(duration <= TimeInterval(minutes * 60))
                        }
                        workout.steps.forEach(assertWholeSeconds)
                    }
                }
            }
        }
    }

    @Test("Every swimming event distance and intent preserves pool geometry")
    func swimmingEventMatrix() throws {
        for kind in EventDistanceKind.choices(for: .swimming) {
            for intent in EventTargetIntent.allCases {
                for minutes in timeOptions {
                    let objective = TrainingObjective.event(
                        sport: .swimming,
                        distance: EventDistance(kind: kind),
                        eventDate: calendar.date(byAdding: .day, value: 28, to: startDate),
                        targetIntent: intent
                    )
                    let plan = try build(
                        sport: .swimming,
                        baseline: AthleteBaseline(swimming: .continuous200Plus),
                        objective: objective,
                        targetDays: 3,
                        minutes: minutes
                    )

                    #expect(plan.trainingSessions.contains { $0.discipline == .swimming })
                    for workout in plan.trainingSessions where workout.discipline == .swimming {
                        workout.steps.forEach(assertWholeSeconds)
                        if let distance = workout.estimatedDistanceMeters {
                            #expect(distance > 0)
                            #expect(distance.truncatingRemainder(dividingBy: 25) == 0)
                        }
                    }
                }
            }
        }
    }

}
