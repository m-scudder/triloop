import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stepTitle: String
        var stepPosition: String
        var repetition: String?
        var isPaused: Bool
        var isCountdown: Bool
        var timerStartedAt: Date?
        var timerEndsAt: Date?
        var frozenSeconds: TimeInterval
    }

    var workoutTitle: String
    var disciplineName: String
}

/// Owns the Lock Screen / Dynamic Island representation of an in-app workout.
/// The Live Activity uses system-driven timer text, so the visible clock keeps
/// ticking while the phone is locked without requiring UI timer callbacks.
@MainActor
final class WorkoutLiveActivityController {
    private var activity: Activity<WorkoutActivityAttributes>?

    func start(
        workoutTitle: String,
        disciplineName: String,
        state: WorkoutActivityAttributes.ContentState
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = WorkoutActivityAttributes(
            workoutTitle: workoutTitle,
            disciplineName: disciplineName
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // A disabled/unavailable Live Activity must never block workout execution.
            activity = nil
        }
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(finalState: WorkoutActivityAttributes.ContentState?) {
        guard let activity else { return }
        self.activity = nil
        Task {
            if let finalState {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}