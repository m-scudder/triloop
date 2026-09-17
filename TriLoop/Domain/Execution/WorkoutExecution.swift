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

    /// Time prescriptions count down. Distance/manual prescriptions use a
    /// stopwatch and advance only when the athlete confirms the step is done.
    var usesCountdown: Bool {
        durationSeconds != nil
    }

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
        steps = Self.flatten(workout.orderedSteps)
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
        // Support nested repeat blocks even though today's prescriptions are
        // shallow. It keeps custom-workout execution deterministic later.
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
                durationSeconds: step.durationSeconds,
                distanceMeters: step.distanceMeters,
                targetIntensity: step.targetIntensity,
                repetition: repetition,
                repetitionCount: repetitionCount
            )
        )
    }
}

struct WorkoutExecutionResult: Equatable, Sendable {
    let workoutID: UUID
    let startedAt: Date
    let endedAt: Date
    /// Active workout time. Paused time is deliberately excluded.
    let elapsedSeconds: TimeInterval
}

/// Pure state machine for the phone workout player.
///
/// It does not own a Timer. The UI feeds elapsed wall-clock deltas into
/// `advance`, which means a suspended/backgrounded UI can catch up correctly on
/// the next pulse rather than relying on a timer firing every second.
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

    /// Advance active time. Countdown steps transition automatically. A
    /// stopwatch/distance step keeps accumulating until `completeCurrentStep`.
    mutating func advance(by seconds: TimeInterval, now: Date = .now) {
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
            } else {
                return
            }
        }
    }

    /// Used for distance-based/manual steps. It is also exposed as Skip in the
    /// player for a timed step when the athlete intentionally moves on early.
    mutating func completeCurrentStep(now: Date = .now) {
        guard phase == .running || phase == .paused, currentStep != nil else { return }
        moveToNextStep(now: now)
    }

    mutating func finish(now: Date = .now) {
        guard phase != .finished else { return }
        if startedAt == nil { startedAt = now }
        endedAt = now
        currentIndex = plan.steps.count
        stepElapsedSeconds = 0
        phase = .finished
    }

    private var stepsContainCurrentIndex: Bool {
        plan.steps.indices.contains(currentIndex)
    }

    private mutating func moveToNextStep(now: Date) {
        currentIndex += 1
        stepElapsedSeconds = 0
        if currentIndex >= plan.steps.count {
            finish(now: now)
        }
    }
}
