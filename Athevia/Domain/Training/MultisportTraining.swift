import Foundation

enum MultisportWorkoutKind: String, Codable, Sendable {
    case runFoundation
    case runEndurance
    case runRacePace
    case brickRun
    case cycleEndurance
    case cycleRacePace
    case brickBike
    case swimFundamentals
    case swimTechnique
    case swimContinuous
    case swimEndurance
    case swimRaceDistance
    case swimOpenWater
    case brick
    case raceSimulation
    case taper
    case raceWeek
    case postEventRecovery
}

enum SwimFoundationState: String, Codable, Sendable {
    case waterComfort
    case breathing
    case shortContinuity
    case continuous
    case endurance

    init(_ baseline: SwimmingBaseline) {
        switch baseline {
        case .none: self = .waterComfort
        case .continuous25: self = .breathing
        case .continuous50: self = .shortContinuity
        case .continuous100: self = .continuous
        case .continuous200Plus: self = .endurance
        }
    }
}

struct OpenWaterTrainingConsent: Codable, Equatable, Sendable {
    var explicitlyConfirmed: Bool
    var hasSafeVenue: Bool
    var hasSupervisionOrBuddy: Bool

    var permitsPrescription: Bool {
        explicitlyConfirmed && hasSafeVenue && hasSupervisionOrBuddy
    }

    static let unavailable = OpenWaterTrainingConsent(
        explicitlyConfirmed: false,
        hasSafeVenue: false,
        hasSupervisionOrBuddy: false
    )
}

struct BrickPrescription: Equatable, Sendable {
    var bikeMeters: Double
    var transitionSeconds: TimeInterval
    var runMeters: Double
    var targetIntensity: TargetIntensity
}

struct MultisportTrainingPolicy: Sendable {
    func canScheduleBrick(
        journey: TrainingJourney,
        objective: TrainingObjective,
        schedule: AthleteSchedule,
        recoveringSports: Set<Sport> = []
    ) -> Bool {
        guard objective.event?.sport == .triathlon,
              journey.phase == .specific,
              schedule.availableDays.count >= 3,
              !recoveringSports.contains(.cycling),
              !recoveringSports.contains(.running) else {
            return false
        }
        return journey.weeklyObjectives.contains { $0.kind == .brickTransition }
    }

    func canScheduleRaceSimulation(
        journey: TrainingJourney,
        objective: TrainingObjective,
        capability: AthleteCapabilityAssessment?,
        nextWeekNumber: Int,
        recoveringSports: Set<Sport> = []
    ) -> Bool {
        guard objective.event?.sport == .triathlon,
              journey.phase == .specific,
              nextWeekNumber.isMultiple(of: 2),
              capability?.completedBrickCount ?? 0 > 0,
              capability?.running.hasDemonstratedCapability == true,
              capability?.cycling.hasDemonstratedCapability == true,
              !recoveringSports.contains(.running),
              !recoveringSports.contains(.cycling) else {
            return false
        }
        return true
    }

    func brick(parameters: TrainingParameters) -> BrickPrescription {
        BrickPrescription(
            bikeMeters: min(parameters.rideWorkDistanceMeters, 10_000),
            transitionSeconds: 5 * 60,
            runMeters: min(
                parameters.runIsContinuous
                    ? parameters.runContinuousDistanceMeters
                    : parameters.runIntervalDistanceMeters * Double(max(parameters.runRepeatCount, 1)),
                2_000
            ),
            targetIntensity: .easy
        )
    }

    func raceSimulation(parameters: TrainingParameters) -> BrickPrescription {
        BrickPrescription(
            bikeMeters: min(parameters.rideWorkDistanceMeters, 15_000),
            transitionSeconds: 5 * 60,
            runMeters: min(
                parameters.runIsContinuous
                    ? parameters.runContinuousDistanceMeters
                    : parameters.runIntervalDistanceMeters * Double(max(parameters.runRepeatCount, 1)),
                3_000
            ),
            targetIntensity: .steady
        )
    }

    func swimKind(
        baseline: SwimmingBaseline,
        phase: TrainingPhase,
        openWater: OpenWaterTrainingConsent? = nil
    ) -> MultisportWorkoutKind {
        if openWater?.permitsPrescription == true, phase == .specific,
           SwimFoundationState(baseline) == .endurance {
            return .swimOpenWater
        }

        switch SwimFoundationState(baseline) {
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

    func workloadMultiplier(for phase: TrainingPhase) -> Double {
        switch phase {
        case .foundation, .build: 1
        case .specific: 1
        case .taper: 0.70
        case .raceWeek: 0.50
        case .recovery: 0
        }
    }
}

enum MultisportPrescribedSessions {
    static func brick(
        on date: Date,
        parameters: TrainingParameters,
        prescription: BrickPrescription
    ) -> PlannedWorkout {
        let steps = [
            WorkoutStep(
                order: 0,
                kind: .cyclingSegment,
                title: "Easy bike",
                instructions: "Pedal gently and get comfortable on the bike.",
                distanceMeters: parameters.rideWarmUpDistanceMeters,
                targetIntensity: .veryEasy
            ),
            WorkoutStep(
                order: 1,
                kind: .cyclingSegment,
                title: "Bike before your run",
                instructions: "Comfortable, controlled riding. Save the legs for the run.",
                distanceMeters: prescription.bikeMeters,
                targetIntensity: prescription.targetIntensity
            ),
            WorkoutStep(
                order: 2,
                kind: .transition,
                title: "Change from bike to run",
                instructions: "Dismount safely, change footwear and start the run without rushing.",
                durationSeconds: prescription.transitionSeconds,
                targetIntensity: .veryEasy
            ),
            WorkoutStep(
                order: 3,
                kind: .runningSegment,
                title: "Easy run after cycling",
                instructions: "Run easy. The purpose is adapting to the bike-to-run change, not speed.",
                distanceMeters: prescription.runMeters,
                targetIntensity: prescription.targetIntensity
            ),
            WorkoutStep(
                order: 4,
                kind: .runningSegment,
                title: "Easy walk",
                distanceMeters: parameters.runCooldownDistanceMeters,
                targetIntensity: .veryEasy
            )
        ]

        return PlannedWorkout(
            date: date,
            discipline: .multisport,
            title: "Brick",
            goal: "Practise how it feels to finish cycling, change shoes, and begin running without rushing.",
            targetRPE: RPERange(3, 5),
            targetDistanceMeters: steps.compactMap(\.totalDistanceMeters).reduce(0, +),
            steps: steps
        )
    }

    static func raceSimulation(
        on date: Date,
        parameters: TrainingParameters,
        prescription: BrickPrescription
    ) -> PlannedWorkout {
        let workout = brick(
            on: date,
            parameters: parameters,
            prescription: prescription
        )
        workout.title = "Race Simulation"
        workout.goal = "Practise event pacing, equipment and transition flow without testing maximum performance."
        workout.targetRPE = RPERange(4, 6)
        if let bike = workout.orderedSteps.first(where: { $0.kind == .cyclingSegment && $0.title == "Bike before your run" }) {
            bike.title = "Controlled event-effort bike"
            bike.instructions = "Use the steady event rhythm you have practised. Keep enough in reserve for the run."
        }
        if let run = workout.orderedSteps.first(where: { $0.kind == .runningSegment && $0.title == "Easy run after cycling" }) {
            run.title = "Controlled event-effort run"
            run.instructions = "Settle quickly after transition. Keep the effort controlled; this is rehearsal, not a test."
        }
        return workout
    }

    static func tapered(
        _ workout: PlannedWorkout,
        multiplier: Double
    ) {
        guard multiplier < 1 else { return }
        if multiplier == 0 {
            workout.title = "Recovery"
            workout.goal = "Recover before beginning the next training objective."
            workout.discipline = .recovery
            workout.targetRPE = nil
            workout.targetDistanceMeters = nil
            workout.prescribedDurationSeconds = 20 * 60
            workout.steps.removeAll()
            workout.steps = [
                WorkoutStep(
                    order: 0,
                    kind: .recovery,
                    title: "Gentle walking and movement",
                    instructions: "Optional easy walking and mobility only.",
                    durationSeconds: 20 * 60,
                    targetIntensity: .veryEasy
                )
            ]
            return
        }
        for step in workout.steps {
            scale(step, multiplier: multiplier)
        }
        if let duration = workout.prescribedDurationSeconds {
            workout.prescribedDurationSeconds = duration * multiplier
        }
        if let distance = workout.targetDistanceMeters {
            workout.targetDistanceMeters = distance * multiplier
        }
    }

    private static func scale(_ step: WorkoutStep, multiplier: Double) {
        if let duration = step.durationSeconds {
            step.durationSeconds = max(duration * multiplier, 60)
        }
        if let distance = step.distanceMeters {
            step.distanceMeters = max(distance * multiplier, 25)
        }
        for child in step.children {
            scale(child, multiplier: multiplier)
        }
    }
}
