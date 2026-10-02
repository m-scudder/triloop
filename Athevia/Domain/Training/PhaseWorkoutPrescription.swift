import Foundation

/// Converts journey phase + current capability into the concrete session type
/// for one schedule slot. Adaptive TrainingParameters remain the load dials;
/// this layer decides what that load means in the current phase.
struct PhaseWorkoutPrescriptionBuilder: Sendable {
    var multisportPolicy = MultisportTrainingPolicy()

    func workout(
        sport: Sport,
        on date: Date,
        parameters: TrainingParameters,
        journey: TrainingJourney?,
        objective: TrainingObjective?,
        capability: AthleteCapabilityAssessment?,
        openWaterConsent: OpenWaterTrainingConsent = .unavailable,
        sportOrdinal: Int = 0
    ) -> PlannedWorkout {
        guard let journey else {
            let workout = PrescribedSessions.session(
                sport.discipline,
                on: date,
                parameters: parameters
            )
            workout.title = sport.discipline.displayName
            return workout
        }

        let current = capability
        let workout: PlannedWorkout

        switch sport {
        case .running:
            workout = running(
                on: date,
                parameters: parameters,
                phase: journey.phase,
                objective: objective,
                capability: current,
                ordinal: sportOrdinal
            )

        case .cycling:
            workout = cycling(
                on: date,
                parameters: parameters,
                phase: journey.phase,
                objective: objective,
                capability: current,
                ordinal: sportOrdinal
            )

        case .swimming:
            workout = swimming(
                on: date,
                parameters: parameters,
                phase: journey.phase,
                objective: objective,
                capability: current,
                openWaterConsent: openWaterConsent,
                ordinal: sportOrdinal
            )
        }

        workout.title = displayTitle(
            sport: sport,
            phase: journey.phase,
            objective: objective,
            ordinal: sportOrdinal
        )
        return workout
    }

    /// Regular training stays deliberately plain: the sport is the workout
    /// name. Event plans may add only a small athletics vocabulary so the title
    /// communicates purpose without inventing a new name for every session.
    private func displayTitle(
        sport: Sport,
        phase: TrainingPhase,
        objective: TrainingObjective?,
        ordinal: Int
    ) -> String {
        guard objective?.kind == .event else {
            return sport.discipline.displayName
        }

        let sportName = sport.discipline.displayName

        switch phase {
        case .foundation:
            return sport == .swimming
                ? "Technique \(sportName)"
                : "Easy \(sportName)"

        case .build:
            return ordinal.isMultiple(of: 2)
                ? "Easy \(sportName)"
                : "Endurance \(sportName)"

        case .specific:
            switch ordinal % 3 {
            case 2:
                return "Race Pace \(sportName)"
            case 1:
                return "Endurance \(sportName)"
            default:
                return sport == .swimming
                    ? "Technique \(sportName)"
                    : "Easy \(sportName)"
            }

        case .taper, .raceWeek:
            return "Easy \(sportName)"

        case .recovery:
            return "Recovery"
        }
    }

    private func running(
        on date: Date,
        parameters: TrainingParameters,
        phase: TrainingPhase,
        objective: TrainingObjective?,
        capability: AthleteCapabilityAssessment?,
        ordinal: Int
    ) -> PlannedWorkout {
        guard parameters.runIsContinuous,
              capability?.running.hasContinuousCapability != false else {
            let workout = PrescribedSessions.runWalk(on: date, parameters: parameters)
            workout.title = "Run / Walk"
            workout.goal = "Build consistency, impact tolerance and relaxed running continuity."
            return workout
        }

        switch phase {
        case .foundation:
            return namedRun(
                on: date,
                parameters: reduced(parameters, sport: .running, by: 0.10),
                title: "Comfortable Run",
                goal: "Build relaxed continuous running without adding intensity.",
                intensity: .easy
            )

        case .build:
            if ordinal.isMultiple(of: 2) {
                return namedRun(
                    on: date,
                    parameters: reduced(parameters, sport: .running, by: 0.20),
                    title: "Easy Run",
                    goal: "Keep aerobic running comfortable between longer sessions.",
                    intensity: .easy
                )
            }
            return namedRun(
                on: date,
                parameters: parameters,
                title: "Longer Comfortable Run",
                goal: "Extend comfortable continuous running at an easy effort.",
                intensity: .easy
            )

        case .specific:
            if ordinal % 3 == 2 {
                let intensity = specificIntensity(
                    objective: objective,
                    supported: capability?.running.hasDemonstratedCapability == true
                )
                return namedRun(
                    on: date,
                    parameters: reduced(parameters, sport: .running, by: 0.25),
                    title: "Practice Your Event Pace",
                    goal: "Practise controlled event-specific rhythm without testing maximum performance.",
                    intensity: intensity
                )
            }
            if ordinal % 3 == 1 {
                return namedRun(
                    on: date,
                    parameters: parameters,
                    title: "Longer Comfortable Run",
                    goal: "Maintain the endurance needed for the event at a conversational effort.",
                    intensity: .easy
                )
            }
            return namedRun(
                on: date,
                parameters: reduced(parameters, sport: .running, by: 0.25),
                title: "Easy Run",
                goal: "Keep easy running familiar around event-specific work.",
                intensity: .easy
            )

        case .taper:
            return namedRun(
                on: date,
                parameters: reduced(parameters, sport: .running, by: 0.20),
                title: "Easy Run",
                goal: "Keep your normal running rhythm while training volume comes down.",
                intensity: .easy
            )

        case .raceWeek:
            return namedRun(
                on: date,
                parameters: reduced(parameters, sport: .running, by: 0.40),
                title: "Short Easy Run Before Your Event",
                goal: "Short, familiar running only. Do not add new stress this week.",
                intensity: .easy
            )

        case .recovery:
            return PrescribedSessions.recoveryDay(
                on: date,
                goal: "Recover before beginning another training block."
            )
        }
    }

    private func cycling(
        on date: Date,
        parameters: TrainingParameters,
        phase: TrainingPhase,
        objective: TrainingObjective?,
        capability: AthleteCapabilityAssessment?,
        ordinal: Int
    ) -> PlannedWorkout {
        switch phase {
        case .foundation:
            if ordinal.isMultiple(of: 2) {
                let ride = PrescribedSessions.easyRide(
                    on: date,
                    parameters: reduced(parameters, sport: .cycling, by: 0.15),
                    goal: "Build bike comfort at an easy conversational effort."
                )
                ride.title = "Comfortable Bike Ride"
                return ride
            }
            return cadenceRide(on: date, parameters: parameters)

        case .build:
            let ride = PrescribedSessions.easyRide(
                on: date,
                parameters: ordinal.isMultiple(of: 2)
                    ? reduced(parameters, sport: .cycling, by: 0.20)
                    : parameters,
                goal: ordinal.isMultiple(of: 2)
                    ? "Keep an easy aerobic ride between longer sessions."
                    : "Build steady cycling endurance without chasing speed."
            )
            ride.title = ordinal.isMultiple(of: 2) ? "Comfortable Bike Ride" : "Longer Comfortable Bike Ride"
            return ride

        case .specific:
            if ordinal.isMultiple(of: 2) {
                let ride = PrescribedSessions.easyRide(
                    on: date,
                    parameters: reduced(parameters, sport: .cycling, by: 0.20),
                    goal: "Practise a controlled event-specific riding rhythm."
                )
                ride.title = "Practice Your Event Riding Pace"
                let intensity = specificIntensity(
                    objective: objective,
                    supported: capability?.cycling.hasDemonstratedCapability == true
                )
                setWorkIntensity(ride, intensity: intensity)
                return ride
            }
            let ride = PrescribedSessions.easyRide(
                on: date,
                parameters: parameters,
                goal: "Maintain event-relevant endurance at a controlled effort."
            )
            ride.title = "Longer Comfortable Bike Ride"
            return ride

        case .taper:
            let ride = PrescribedSessions.easyRide(
                on: date,
                parameters: reduced(parameters, sport: .cycling, by: 0.20),
                goal: "Keep normal pedalling rhythm while volume comes down."
            )
            ride.title = "Comfortable Bike Ride"
            return ride

        case .raceWeek:
            let ride = PrescribedSessions.easyRide(
                on: date,
                parameters: reduced(parameters, sport: .cycling, by: 0.40),
                goal: "Short, familiar riding only. Do not add new stress this week."
            )
            ride.title = "Race-Week Comfortable Bike Ride"
            return ride

        case .recovery:
            return PrescribedSessions.recoveryDay(
                on: date,
                goal: "Recover before beginning another training block."
            )
        }
    }

    private func swimming(
        on date: Date,
        parameters: TrainingParameters,
        phase: TrainingPhase,
        objective: TrainingObjective?,
        capability: AthleteCapabilityAssessment?,
        openWaterConsent: OpenWaterTrainingConsent,
        ordinal: Int
    ) -> PlannedWorkout {
        if phase == .recovery {
            return PrescribedSessions.recoveryDay(
                on: date,
                goal: "Recover before beginning another training block."
            )
        }

        let swimCapability = capability?.swimming
        let state = swimCapability?.foundationState
            ?? SwimFoundationState(continuousMeters: parameters.swimRepeatDistanceMeters)

        let eventRequiresSwimming = objective?.event?.sport.requiredTrainingSports.contains(.swimming) == true
        let openWaterPermitted = phase == .specific
            && eventRequiresSwimming
            && openWaterConsent.permitsPrescription
            && state == .endurance
            && capability?.recoveryState == .stable

        // Pool geometry is a venue constraint, never capability evidence. A
        // swimmer who has only demonstrated less than one full length of this
        // pool must not be promoted to a full-length repeat by normalization.
        let poolLength = max(parameters.swimPoolLengthMeters, 25)
        let supportedContinuousMeters = swimCapability?.recentLongestProvenContinuousMeters
            ?? swimCapability?.reportedContinuousMeters
            ?? swimCapability?.longestProvenContinuousMeters
            ?? parameters.swimRepeatDistanceMeters
        if supportedContinuousMeters > 0,
           supportedContinuousMeters < poolLength {
            return poolGeometryFundamentals(
                on: date,
                poolLengthMeters: poolLength
            )
        }

        let kind = multisportPolicy.swimKind(
            foundationState: state,
            phase: phase,
            openWaterPermitted: openWaterPermitted
        )

        switch kind {
        case .swimFundamentals:
            return swimFundamentals(on: date, parameters: parameters, state: state)
        case .swimTechnique:
            return repeatSwim(
                on: date,
                parameters: parameters,
                repeatMeters: 50,
                title: "Practice Comfortable Swimming",
                goal: "Repeat relaxed 50 m efforts with enough rest to keep technique consistent."
            )
        case .swimContinuous:
            return repeatSwim(
                on: date,
                parameters: parameters,
                repeatMeters: 100,
                title: "Swim Longer With Short Rests",
                goal: "Develop longer continuous blocks without turning total volume into one uninterrupted effort."
            )
        case .swimEndurance:
            return repeatSwim(
                on: date,
                parameters: parameters,
                repeatMeters: max(100, min(swimCapability?.currentContinuousMeters ?? 200, 200)),
                title: "Longer Comfortable Swim",
                goal: "Build controlled swimming endurance through repeatable blocks."
            )
        case .swimRaceDistance:
            let eventMeters = objective?.event?.distance?.components.swimMeters ?? parameters.swimTotalMeters
            let block = min(max(100, (swimCapability?.currentContinuousMeters ?? 100)), max(eventMeters * 0.5, 100))
            return repeatSwim(
                on: date,
                parameters: parameters,
                repeatMeters: block,
                title: "Practice for Your Event Swim",
                goal: "Practise event-relevant swim blocks without repeatedly swimming the full event distance."
            )
        case .swimOpenWater:
            return openWaterSwim(on: date, parameters: parameters)
        case .taper, .raceWeek:
            return repeatSwim(
                on: date,
                parameters: reduced(parameters, sport: .swimming, by: phase == .raceWeek ? 0.40 : 0.20),
                repeatMeters: min(max(parameters.swimRepeatDistanceMeters, 25), 100),
                title: phase == .raceWeek ? "Short Easy Swim Before Your Event" : "Easy Practice Comfortable Swimming",
                goal: "Keep familiar swim rhythm while volume comes down."
            )
        default:
            // Run/cycle/brick kinds never enter the swim builder.
            return PrescribedSessions.techniqueSwim(on: date, parameters: parameters)
        }
    }

    private func namedRun(
        on date: Date,
        parameters: TrainingParameters,
        title: String,
        goal: String,
        intensity: TargetIntensity
    ) -> PlannedWorkout {
        let workout = PrescribedSessions.runWalk(on: date, parameters: parameters, goal: goal)
        workout.title = title
        setWorkIntensity(workout, intensity: intensity)
        return workout
    }

    private func cadenceRide(
        on date: Date,
        parameters: TrainingParameters
    ) -> PlannedWorkout {
        let work = max(parameters.rideWorkSeconds, 10 * 60)
        let cadenceBlock = max(min(work / 5, 5 * 60), 2 * 60)
        let steps: [WorkoutStep] = [
            .warmUp(order: 0, title: "Easy spinning", durationSeconds: parameters.rideWarmUpSeconds),
            .repeating(
                order: 1,
                title: "Practice smooth pedaling",
                count: 3,
                instructions: "Smooth pedalling, not harder pedalling.",
                children: [
                    WorkoutStep(
                        order: 0,
                        kind: .work,
                        title: "Smooth, quick pedaling",
                        durationSeconds: cadenceBlock,
                        targetIntensity: .easy
                    ),
                    WorkoutStep(
                        order: 1,
                        kind: .recovery,
                        title: "Easy spin",
                        durationSeconds: 60,
                        targetIntensity: .veryEasy
                    )
                ]
            ),
            .cooldown(order: 2, title: "Easy spinning", durationSeconds: parameters.rideCooldownSeconds)
        ]
        return PlannedWorkout(
            date: date,
            discipline: .cycling,
            title: "Practice Smooth Pedaling",
            goal: "Build bike comfort and smooth cadence without adding intensity.",
            targetRPE: RPERange(3, 4),
            steps: steps
        )
    }

    private func swimFundamentals(
        on date: Date,
        parameters: TrainingParameters,
        state: SwimFoundationState
    ) -> PlannedWorkout {
        if state == .waterComfort {
            return PlannedWorkout(
                date: date,
                discipline: .swimming,
                title: "Learn the Basics of Swimming",
                goal: "Learn basic water confidence and breathing with supervised instruction before endurance progression.",
                targetRPE: RPERange(1, 3),
                prescribedDurationSeconds: 20 * 60,
                steps: [
                    WorkoutStep(
                        order: 0,
                        kind: .work,
                        title: "Supervised water confidence",
                        instructions: "Only practise with qualified supervision. Focus on safe entry, relaxed exhalation and supported floating. Stop if you do not feel safe.",
                        durationSeconds: 20 * 60,
                        targetIntensity: .veryEasy
                    )
                ]
            )
        }

        return repeatSwim(
            on: date,
            parameters: parameters,
            repeatMeters: 25,
            title: "Learn the Basics of Swimming",
            goal: "Practise breathing and relaxation over short lengths with full recovery."
        )
    }

    private func poolGeometryFundamentals(
        on date: Date,
        poolLengthMeters: Double
    ) -> PlannedWorkout {
        PlannedWorkout(
            date: date,
            discipline: .swimming,
            title: "Learn the Basics of Swimming",
            goal: "Build water confidence and breathing safely without treating pool length as demonstrated continuous capability.",
            targetRPE: RPERange(1, 3),
            prescribedDurationSeconds: 20 * 60,
            steps: [
                WorkoutStep(
                    order: 0,
                    kind: .work,
                    title: "Supervised fundamentals practice",
                    instructions: "Use a shorter pool or supervised/coached practice until one full \(Int(poolLengthMeters)) m length can be completed safely and comfortably. Do not practise alone.",
                    durationSeconds: 20 * 60,
                    targetIntensity: .veryEasy
                )
            ]
        )
    }

    private func repeatSwim(
        on date: Date,
        parameters: TrainingParameters,
        repeatMeters: Double,
        title: String,
        goal: String
    ) -> PlannedWorkout {
        let pool = max(parameters.swimPoolLengthMeters, 25)
        let normalizedRepeat = max(
            pool,
            (repeatMeters / pool).rounded() * pool
        )
        let total = max(parameters.swimTotalMeters, normalizedRepeat)
        let count = max(Int((total / normalizedRepeat).rounded(.down)), 1)
        let rest = max(parameters.swimRestSeconds, TrainingParameters.Limits.restFloor(forRepeat: normalizedRepeat))

        let block = WorkoutStep.repeating(
            order: 0,
            title: "\(count) × \(Int(normalizedRepeat)) m",
            count: count,
            instructions: "Keep every repeat controlled. Rest enough to preserve form.",
            children: [
                WorkoutStep(
                    order: 0,
                    kind: .work,
                    title: "Relaxed swim",
                    distanceMeters: normalizedRepeat,
                    targetIntensity: .easy
                ),
                WorkoutStep(
                    order: 1,
                    kind: .recovery,
                    title: "Rest",
                    durationSeconds: rest,
                    targetIntensity: .veryEasy
                )
            ]
        )

        return PlannedWorkout(
            date: date,
            discipline: .swimming,
            title: title,
            goal: goal,
            targetRPE: RPERange(3, 5),
            targetDistanceMeters: normalizedRepeat * Double(count),
            steps: [block]
        )
    }

    private func openWaterSwim(
        on date: Date,
        parameters: TrainingParameters
    ) -> PlannedWorkout {
        let duration = max(min(parameters.swimTotalMeters * 2.2, 30 * 60), 15 * 60)
        return PlannedWorkout(
            date: date,
            discipline: .swimming,
            title: "Practice Swimming in Open Water",
            goal: "Practise calm open-water familiarity only at the confirmed safe venue with your buddy or supervision.",
            targetRPE: RPERange(3, 5),
            prescribedDurationSeconds: duration,
            steps: [
                WorkoutStep(
                    order: 0,
                    kind: .work,
                    title: "Easy open-water swim",
                    instructions: "Stay with your buddy or supervision. Practise relaxed sighting and orientation; this is not a distance test.",
                    durationSeconds: duration,
                    targetIntensity: .easy
                )
            ]
        )
    }

    private func specificIntensity(
        objective: TrainingObjective?,
        supported: Bool
    ) -> TargetIntensity {
        guard let intent = objective?.event?.targetIntent else { return .steady }
        switch intent {
        case .finishComfortably:
            return .easy
        case .complete:
            return .steady
        case .performance:
            return supported ? .moderate : .steady
        }
    }

    private func reduced(
        _ parameters: TrainingParameters,
        sport: Sport,
        by fraction: Double
    ) -> TrainingParameters {
        parameters.applying(.reduceVolume(fraction: fraction), to: sport)
    }

    private func setWorkIntensity(
        _ workout: PlannedWorkout,
        intensity: TargetIntensity
    ) {
        func apply(_ step: WorkoutStep) {
            if step.kind == .work {
                step.targetIntensity = intensity
            }
            step.children.forEach(apply)
        }
        workout.steps.forEach(apply)
    }
}

extension MultisportTrainingPolicy {
    func swimKind(
        foundationState: SwimFoundationState,
        phase: TrainingPhase,
        openWaterPermitted: Bool
    ) -> MultisportWorkoutKind {
        if openWaterPermitted, phase == .specific, foundationState == .endurance {
            return .swimOpenWater
        }
        if phase == .taper { return .taper }
        if phase == .raceWeek { return .raceWeek }

        switch foundationState {
        case .waterComfort, .breathing:
            return .swimFundamentals
        case .shortContinuity:
            return .swimTechnique
        case .continuous:
            return .swimContinuous
        case .endurance:
            return phase == .specific ? .swimRaceDistance : .swimEndurance
        }
    }
}
