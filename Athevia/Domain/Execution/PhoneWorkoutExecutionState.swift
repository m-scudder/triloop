import Foundation

/// Coordinates the one phone-owned workout execution with background plan
/// reconciliation. HealthKit/WorkoutKit may update the same planned session
/// while the full-screen player is open; those updates must not tear down the
/// player or mark the session complete underneath the athlete.
@MainActor
enum PhoneWorkoutExecutionState {
    private(set) static var activeWorkoutID: UUID?

    static var isActive: Bool {
        activeWorkoutID != nil
    }

    static func begin(_ workoutID: UUID) {
        activeWorkoutID = workoutID
    }

    static func end(_ workoutID: UUID) {
        guard activeWorkoutID == workoutID else { return }
        activeWorkoutID = nil
    }
}
