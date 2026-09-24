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

struct OpenWaterTrainingConsent: Equatable, Sendable {
    var explicitlyConfirmed: Bool
    var hasSafeVenue: Bool
    var hasSupervisionOrBuddy: Bool

    var permitsPrescription: Bool {
        explicitlyConfirmed && hasSafeVenue && hasSupervisionOrBuddy
    }
}

struct BrickPrescription: Equatable, Sendable {
    var bikeSeconds: TimeInterval
    var transitionSeconds: TimeInterval
    var runSeconds: TimeInterval
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

    func brick(parameters: TrainingParameters) -> BrickPrescription {
        BrickPrescription(
            bikeSeconds: min(parameters.rideWorkSeconds, 45 * 60),
            transitionSeconds: 5 * 60,
            runSeconds: min(
                parameters.runIsContinuous
                    ? parameters.runContinuousSeconds
                    : parameters.runIntervalSeconds * Double(max(parameters.runRepeatCount, 1)),
                15 * 60
            ),
            targetIntensity: .easy
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
        case .waterComfort, .breathing: .swimFundamentals
        case .shortContinuity: .swimTechnique
        case .continuous: .swimContinuous
        case .endurance: phase == .specific ? .swimRaceDistance : .swimEndurance
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
                kind: .warmUp,
                title: "Easy bike",
                instructions: "Settle into a relaxed cadence.",
                durationSeconds: parameters.rideWarmUpSeconds,
                targetIntensity: .veryEasy
            ),
            WorkoutStep(
                order: 1,
                kind: .work,
                title: "Brick bike",
                instructions: "Comfortable, controlled riding. Save the legs for the run.",
                durationSeconds: prescription.bikeSeconds,
                targetIntensity: prescription.targetIntensity
            ),
            WorkoutStep(
                order: 2,
                kind: .recovery,
                title: "Transition",
                instructions: "Dismount safely, change footwear and start the run without rushing.",
                durationSeconds: prescription.transitionSeconds,
                targetIntensity: .veryEasy
            ),
            WorkoutStep(
                order: 3,
                kind: .work,
                title: "Brick run",
                instructions: "Run easy. The purpose is adapting to the bike-to-run change, not speed.",
                durationSeconds: prescription.runSeconds,
                targetIntensity: prescription.targetIntensity
            ),
            WorkoutStep.cooldown(
                order: 4,
                title: "Easy walk",
                durationSeconds: parameters.runCooldownSeconds
            )
        ]

        // Cycling is the owning discipline so the existing execution stack can
        // launch one deterministic sequential session. The explicit step titles
        // preserve Bike -> Transition -> Run for phone/watch/audio.
        return PlannedWorkout(
            date: date,
            discipline: .cycling,
            title: "Bike + Run Brick",
            goal: "Practise a calm bike-to-run transition at easy effort.",
            targetRPE: RPERange(3, 5),
            steps: steps
        )
    }

    static func tapered(
        _ workout: PlannedWorkout,
        multiplier: Double
    ) {
        guard multiplier < 1 else { return }
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
