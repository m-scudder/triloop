import Foundation

enum WorkoutSchedulingAuthorization: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

enum WorkoutSchedulingError: Error, Equatable {
    /// The session has no structure WorkoutKit can express, or the sport is not
    /// supported for custom workouts.
    case unsupportedWorkout
    case notAuthorized
    /// No paired Watch, or scheduling is unavailable on this device.
    case unavailable
    /// `schedule` reported nothing, but the workout is absent afterwards.
    case notAccepted
}

/// What the Watch currently holds in its schedule.
struct ScheduledWorkoutSummary: Equatable, Sendable, Identifiable {
    let id: UUID
    let displayName: String?
    let date: Date?
    let isComplete: Bool
}

/// §24's boundary for sending workouts to Apple Watch.
protocol WorkoutScheduling: Sendable {
    var isSupported: Bool { get }
    func authorizationState() async -> WorkoutSchedulingAuthorization
    func requestAuthorization() async -> WorkoutSchedulingAuthorization
    func schedule(_ workout: PlannedWorkout, at date: Date) async throws
    func scheduledWorkouts() async -> [ScheduledWorkoutSummary]
}

extension WorkoutScheduling {
    func scheduledWorkoutIDs() async -> Set<UUID> {
        Set(await scheduledWorkouts().map(\.id))
    }
}

/// Records what would have been scheduled, for previews and tests.
final class StubWorkoutScheduler: WorkoutScheduling, @unchecked Sendable {
    var isSupported: Bool
    private(set) var scheduled: [(workoutID: UUID, date: Date)] = []
    private var state: WorkoutSchedulingAuthorization

    init(isSupported: Bool = true, state: WorkoutSchedulingAuthorization = .authorized) {
        self.isSupported = isSupported
        self.state = state
    }

    func authorizationState() async -> WorkoutSchedulingAuthorization { state }

    func requestAuthorization() async -> WorkoutSchedulingAuthorization {
        if state == .notDetermined { state = .authorized }
        return state
    }

    func schedule(_ workout: PlannedWorkout, at date: Date) async throws {
        guard isSupported else { throw WorkoutSchedulingError.unavailable }
        guard state == .authorized else { throw WorkoutSchedulingError.notAuthorized }
        guard WorkoutPlanBuilder.plan(for: workout) != nil else {
            throw WorkoutSchedulingError.unsupportedWorkout
        }
        scheduled.append((workout.id, date))
    }

    func scheduledWorkouts() async -> [ScheduledWorkoutSummary] {
        scheduled.map {
            ScheduledWorkoutSummary(
                id: $0.workoutID,
                displayName: nil,
                date: $0.date,
                isComplete: false
            )
        }
    }
}
