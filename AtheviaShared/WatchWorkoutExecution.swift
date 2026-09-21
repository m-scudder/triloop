import Foundation

struct WatchExecutableWorkoutStep: Equatable, Identifiable, Sendable {
    let id: String
    let sourceStepID: UUID
    let kind: WatchWorkoutStepKind
    let title: String
    let instructions: String?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let targetIntensity: WatchWorkoutIntensity?
    let repetition: Int?
    let repetitionCount: Int?

    var repetitionLabel: String? {
        guard let repetition, let repetitionCount else { return nil }
        return "Round \(repetition) of \(repetitionCount)"
    }
}

struct WatchWorkoutExecutionPlan: Equatable, Sendable {
    let workoutID: UUID
    let title: String
    let steps: [WatchExecutableWorkoutStep]

    init(workout: WatchWorkoutPayload) {
        workoutID = workout.id
        title = workout.title
        steps = Self.flatten(workout.steps)
    }

    private static func flatten(_ source: [WatchWorkoutStepPayload]) -> [WatchExecutableWorkoutStep] {
        var output: [WatchExecutableWorkoutStep] = []

        func append(
            _ step: WatchWorkoutStepPayload,
            repetition: Int? = nil,
            repetitionCount: Int? = nil,
            path: String
        ) {
            if step.kind == .repeatBlock {
                let count = max(step.repeatCount ?? 1, 1)
                for round in 1...count {
                    for child in step.children {
                        append(
                            child,
                            repetition: round,
                            repetitionCount: count,
                            path: "\(path)-\(round)-\(child.id.uuidString)"
                        )
                    }
                }
                return
            }

            output.append(
                WatchExecutableWorkoutStep(
                    id: "\(path)-\(output.count)",
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

        for step in source {
            append(step, path: step.id.uuidString)
        }

        return output
    }
}

struct WatchWorkoutExecutionSnapshot: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Equatable, Sendable {
        case ready
        case running
        case paused
        case finished
    }

    let workoutID: UUID
    let phase: Phase
    let currentIndex: Int
    let elapsedSeconds: TimeInterval
    let stepElapsedSeconds: TimeInterval
    let stepDistanceMeters: Double
}

struct WatchWorkoutExecutionEngine: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case ready
        case running
        case paused
        case finished
    }

    let plan: WatchWorkoutExecutionPlan

    private(set) var phase: Phase = .ready
    private(set) var currentIndex = 0
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var stepElapsedSeconds: TimeInterval = 0
    private(set) var stepDistanceMeters: Double = 0

    var currentStep: WatchExecutableWorkoutStep? {
        guard plan.steps.indices.contains(currentIndex) else { return nil }
        return plan.steps[currentIndex]
    }

    var nextStep: WatchExecutableWorkoutStep? {
        let next = currentIndex + 1
        guard plan.steps.indices.contains(next) else { return nil }
        return plan.steps[next]
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

    var stepProgress: Double? {
        if let duration = currentStep?.durationSeconds, duration > 0 {
            return min(max(stepElapsedSeconds / duration, 0), 1)
        }
        if let distance = currentStep?.distanceMeters, distance > 0 {
            return min(max(stepDistanceMeters / distance, 0), 1)
        }
        return nil
    }

    init(workout: WatchWorkoutPayload) {
        plan = WatchWorkoutExecutionPlan(workout: workout)
    }

    init(
        workout: WatchWorkoutPayload,
        snapshot: WatchWorkoutExecutionSnapshot
    ) {
        plan = WatchWorkoutExecutionPlan(workout: workout)

        guard snapshot.workoutID == workout.id else { return }

        currentIndex = min(max(snapshot.currentIndex, 0), plan.steps.count)
        elapsedSeconds = max(snapshot.elapsedSeconds, 0)
        stepElapsedSeconds = max(snapshot.stepElapsedSeconds, 0)
        stepDistanceMeters = max(snapshot.stepDistanceMeters, 0)

        if currentIndex >= plan.steps.count {
            phase = .finished
            return
        }

        phase = switch snapshot.phase {
        case .ready: .ready
        case .running: .running
        case .paused: .paused
        case .finished: .finished
        }
    }

    var snapshot: WatchWorkoutExecutionSnapshot {
        WatchWorkoutExecutionSnapshot(
            workoutID: plan.workoutID,
            phase: switch phase {
            case .ready: .ready
            case .running: .running
            case .paused: .paused
            case .finished: .finished
            },
            currentIndex: currentIndex,
            elapsedSeconds: elapsedSeconds,
            stepElapsedSeconds: stepElapsedSeconds,
            stepDistanceMeters: stepDistanceMeters
        )
    }

    mutating func start() {
        guard phase == .ready else { return }
        phase = plan.steps.isEmpty ? .finished : .running
    }

    mutating func pause() {
        guard phase == .running else { return }
        phase = .paused
    }

    mutating func resume() {
        guard phase == .paused else { return }
        phase = .running
    }

    mutating func advance(by seconds: TimeInterval, distanceDeltaMeters: Double = 0) {
        guard phase == .running, currentStep != nil else { return }

        if seconds > 0 {
            elapsedSeconds += seconds
        }

        var remainingTime = max(seconds, 0)
        var remainingDistance = max(distanceDeltaMeters, 0)

        while phase == .running, let step = currentStep {
            if let duration = step.durationSeconds {
                let needed = max(duration - stepElapsedSeconds, 0)
                let consumed = min(remainingTime, needed)
                stepElapsedSeconds += consumed
                remainingTime -= consumed

                if stepElapsedSeconds >= duration {
                    moveToNextStep()
                    continue
                }
                return
            }

            if let distance = step.distanceMeters {
                let needed = max(distance - stepDistanceMeters, 0)
                let consumed = min(remainingDistance, needed)
                stepDistanceMeters += consumed
                remainingDistance -= consumed

                if stepDistanceMeters >= distance {
                    moveToNextStep()
                    continue
                }
                return
            }

            stepElapsedSeconds += remainingTime
            return
        }
    }

    mutating func completeCurrent() {
        guard phase == .running || phase == .paused, currentStep != nil else { return }
        let wasPaused = phase == .paused
        moveToNextStep()
        if wasPaused, phase != .finished {
            phase = .paused
        }
    }

    mutating func finish() {
        currentIndex = plan.steps.count
        stepElapsedSeconds = 0
        stepDistanceMeters = 0
        phase = .finished
    }

    private mutating func moveToNextStep() {
        currentIndex += 1
        stepElapsedSeconds = 0
        stepDistanceMeters = 0
        if currentIndex >= plan.steps.count {
            phase = .finished
        }
    }
}
