import Foundation

/// One concrete step the in-app player can execute.
///
/// Persisted workout steps intentionally keep repeat blocks compact. The player
/// expands them so the athlete sees the exact sequence they need to follow.
struct ExecutableWorkoutStep: Equatable, Identifiable, Sendable {
    let id: String
    let sourceStepID: UUID
    let kind: WorkoutStepKind
    let title: String
    let instructions: String?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let targetIntensity: TargetIntensity?
    let repetition: Int?
    let repetitionCount: Int?

    /// Time prescriptions count down. Distance prescriptions progress from
    /// recorded distance. A step with neither remains manually completed.
    var usesCountdown: Bool { durationSeconds != nil }

    var repetitionLabel: String? {
        guard let repetition, let repetitionCount else { return nil }
        return "Round \(repetition) of \(repetitionCount)"
    }
}

struct WorkoutExecutionPlan: Equatable, Sendable {
    let workoutID: UUID
    let title: String
    let steps: [ExecutableWorkoutStep]

    @MainActor
    init(workout: PlannedWorkout) {
        workoutID = workout.id
        title = workout.title

        let structured = Self.flatten(workout.orderedSteps)
        if !structured.isEmpty {
            steps = structured
            return
        }

        // Legacy/simple sessions can carry only a workout-level prescription.
        // They still need one executable step; an empty plan would otherwise
        // transition from ready -> finished the instant Start is tapped.
        let rawDuration = workout.prescribedDurationSeconds
            ?? workout.estimatedDurationSeconds
        let duration = Self.validPositive(rawDuration)
        let distance = Self.validPositive(workout.estimatedDistanceMeters)

        // A training session with no structured blocks is still executable as
        // one manual/whole-workout step. This guarantees Start can never mean
        // Complete merely because persistence contains no child rows.
        steps = [
            ExecutableWorkoutStep(
                id: "fallback-\(workout.id.uuidString)",
                sourceStepID: workout.id,
                kind: .work,
                title: workout.title,
                instructions: workout.goal.isEmpty ? nil : workout.goal,
                durationSeconds: duration,
                distanceMeters: duration == nil ? distance : nil,
                targetIntensity: nil,
                repetition: nil,
                repetitionCount: nil
            )
        ]
    }

    @MainActor
    private static func flatten(_ source: [WorkoutStep]) -> [ExecutableWorkoutStep] {
        var result: [ExecutableWorkoutStep] = []

        for step in source {
            if step.kind == .repeatBlock {
                let count = max(step.repeatCount ?? 1, 1)
                for repetition in 1...count {
                    for child in step.orderedChildren {
                        append(
                            child,
                            repetition: repetition,
                            repetitionCount: count,
                            path: "\(step.id.uuidString)-\(repetition)",
                            to: &result
                        )
                    }
                }
            } else {
                append(step, path: step.id.uuidString, to: &result)
            }
        }

        return result
    }

    @MainActor
    private static func append(
        _ step: WorkoutStep,
        repetition: Int? = nil,
        repetitionCount: Int? = nil,
        path: String,
        to result: inout [ExecutableWorkoutStep]
    ) {
        if step.kind == .repeatBlock {
            let count = max(step.repeatCount ?? 1, 1)
            for nestedRepetition in 1...count {
                for child in step.orderedChildren {
                    append(
                        child,
                        repetition: nestedRepetition,
                        repetitionCount: count,
                        path: "\(path)-\(step.id.uuidString)-\(nestedRepetition)",
                        to: &result
                    )
                }
            }
            return
        }

        result.append(
            ExecutableWorkoutStep(
                id: "\(path)-\(step.id.uuidString)-\(result.count)",
                sourceStepID: step.id,
                kind: step.kind,
                title: step.title,
                instructions: step.instructions,
                durationSeconds: validPositive(step.durationSeconds),
                distanceMeters: validPositive(step.distanceMeters),
                targetIntensity: step.targetIntensity,
                repetition: repetition,
                repetitionCount: repetitionCount
            )
        )
    }

    private static func validPositive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

struct WorkoutExecutionResult: Equatable, Sendable {
    let workoutID: UUID
    let startedAt: Date
    let endedAt: Date
    /// Active workout time. Paused time is deliberately excluded.
    let elapsedSeconds: TimeInterval
    /// Phone GPS evidence. Nil/empty for swims, indoor sessions or denied
    /// location permission; workout execution never depends on GPS succeeding.
    let distanceMeters: Double?
    let route: [RecordedRoutePoint]
    let multisportSegments: [RecordedMultisportSegment]

    init(
        workoutID: UUID,
        startedAt: Date,
        endedAt: Date,
        elapsedSeconds: TimeInterval,
        distanceMeters: Double? = nil,
        route: [RecordedRoutePoint] = [],
        multisportSegments: [RecordedMultisportSegment] = []
    ) {
        self.workoutID = workoutID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.elapsedSeconds = elapsedSeconds
        self.distanceMeters = distanceMeters
        self.route = route
        self.multisportSegments = multisportSegments
    }
}

/// Pure state machine for the phone workout player.
///
/// It does not own a Timer. The UI feeds elapsed wall-clock deltas into
/// `advance`. Normal foreground pulses can flow across timed steps; after a
/// long suspension the caller can restrict catch-up to the step that was
/// actually active so later sets are never inferred as completed.
struct WorkoutExecutionEngine: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case ready
        case running
        case paused
        case finished
    }

    let plan: WorkoutExecutionPlan
    private(set) var phase: Phase = .ready
    private(set) var currentIndex = 0
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var stepElapsedSeconds: TimeInterval = 0
    private(set) var stepDistanceMeters: Double = 0
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?

    var currentStep: ExecutableWorkoutStep? {
        guard stepsContainCurrentIndex else { return nil }
        return plan.steps[currentIndex]
    }

    var nextStep: ExecutableWorkoutStep? {
        let index = currentIndex + 1
        guard plan.steps.indices.contains(index) else { return nil }
        return plan.steps[index]
    }

    var remainingSeconds: TimeInterval? {
        guard let duration = currentStep?.durationSeconds else { return nil }
        return max(duration - stepElapsedSeconds, 0)
    }

    var remainingDistanceMeters: Double? {
        guard currentStep?.durationSeconds == nil,
              let distance = currentStep?.distanceMeters else { return nil }
        return max(distance - stepDistanceMeters, 0)
    }

    var result: WorkoutExecutionResult? {
        guard phase == .finished, let startedAt, let endedAt else { return nil }
        return WorkoutExecutionResult(
            workoutID: plan.workoutID,
            startedAt: startedAt,
            endedAt: endedAt,
            elapsedSeconds: elapsedSeconds
        )
    }

    init(plan: WorkoutExecutionPlan) {
        self.plan = plan
    }

    mutating func start(now: Date = .now) {
        guard phase == .ready else { return }
        startedAt = now

        guard !plan.steps.isEmpty else {
            endedAt = now
            phase = .finished
            return
        }
        phase = .running
    }

    mutating func pause() {
        guard phase == .running else { return }
        phase = .paused
    }

    mutating func resume() {
        guard phase == .paused else { return }
        phase = .running
    }

    /// Advance active time. Countdown steps transition automatically. Distance
    /// and manual steps keep accumulating elapsed time while distance itself is
    /// supplied separately by `updateCurrentStepDistance`.
    ///
    /// A normal pulse can carry elapsed time across timed steps. This is also
    /// used when the app returns from the background.
    mutating func advance(
        by seconds: TimeInterval,
        now: Date = .now,
        allowsCascading: Bool = true
    ) {
        guard phase == .running, seconds > 0, currentStep != nil else { return }

        var remainingDelta = seconds
        while remainingDelta > 0, phase == .running, let step = currentStep {
            guard let duration = step.durationSeconds else {
                stepElapsedSeconds += remainingDelta
                elapsedSeconds += remainingDelta
                return
            }

            let leftInStep = max(duration - stepElapsedSeconds, 0)
            let consumed = min(remainingDelta, leftInStep)
            stepElapsedSeconds += consumed
            elapsedSeconds += consumed
            remainingDelta -= consumed

            if stepElapsedSeconds >= duration {
                moveToNextStep(now: now)
                if !allowsCascading { return }
            } else {
                return
            }
        }
    }

    /// Update distance covered inside the currently active distance step.
    /// The caller supplies distance relative to the beginning of this step so
    /// warm-up/cool-down GPS does not count toward the work target.
    mutating func updateCurrentStepDistance(
        _ meters: Double,
        now: Date = .now
    ) {
        guard phase == .running,
              let target = currentStep?.distanceMeters,
              currentStep?.durationSeconds == nil,
              target > 0 else { return }

        stepDistanceMeters = min(max(meters, 0), target)
        if stepDistanceMeters >= target {
            moveToNextStep(now: now)
        }
    }

    /// Used for manual steps and as Skip when the athlete intentionally moves on.
    mutating func completeCurrentStep(now: Date = .now) {
        guard phase == .running || phase == .paused, currentStep != nil else { return }
        let shouldStartNextStep = phase == .paused
        moveToNextStep(now: now)

        // Completing a set is an explicit transition, not a request to keep the
        // following set paused. If there is another set, start it immediately.
        if shouldStartNextStep, phase == .paused {
            phase = .running
        }
    }

    mutating func finish(now: Date = .now) {
        guard phase != .finished else { return }
        if startedAt == nil { startedAt = now }
        endedAt = now
        currentIndex = plan.steps.count
        stepElapsedSeconds = 0
        stepDistanceMeters = 0
        phase = .finished
    }

    private var stepsContainCurrentIndex: Bool {
        plan.steps.indices.contains(currentIndex)
    }

    private mutating func moveToNextStep(now: Date) {
        currentIndex += 1
        stepElapsedSeconds = 0
        stepDistanceMeters = 0
        if currentIndex >= plan.steps.count {
            finish(now: now)
        }
    }
}