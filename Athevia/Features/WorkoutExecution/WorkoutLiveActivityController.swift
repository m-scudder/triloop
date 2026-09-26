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
        var gamingThemeEnabled: Bool? = nil
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
    private static var pending: [String: (id: UUID, task: Task<Void, Never>)] = [:]

    private static func themed(_ state: WorkoutActivityAttributes.ContentState) -> WorkoutActivityAttributes.ContentState {
        var copy = state
        copy.gamingThemeEnabled = AtheviaTheme.stored().isGaming
        return copy
    }

    /// Serialize cosmetic updates with step/timer updates. Read the activity's
    /// latest state inside the queue so a theme change cannot restore an old step.
    private static func enqueue(
        for activity: Activity<WorkoutActivityAttributes>,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let previous = pending[activity.id]?.task
        let id = UUID()
        let task = Task { @MainActor in
            await previous?.value
            await operation()
            if pending[activity.id]?.id == id { pending[activity.id] = nil }
        }
        pending[activity.id] = (id, task)
        return task
    }

    static func refreshTheme() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            let task = enqueue(for: activity) {
                guard activity.activityState == .active || activity.activityState == .stale else { return }
                let content = ActivityContent(state: themed(activity.content.state), staleDate: activity.content.staleDate)
                await activity.update(content)
            }
            await task.value
        }
    }

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
                content: ActivityContent(state: Self.themed(state), staleDate: nil),
                pushType: nil
            )
        } catch {
            // A disabled/unavailable Live Activity must never block workout execution.
            activity = nil
        }
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        Self.enqueue(for: activity) {
            await activity.update(ActivityContent(state: Self.themed(state), staleDate: nil))
        }
    }

    func end(finalState: WorkoutActivityAttributes.ContentState?) {
        guard let activity else { return }
        self.activity = nil
        Self.enqueue(for: activity) {
            if let finalState {
                await activity.end(
                    ActivityContent(state: Self.themed(finalState), staleDate: nil),
                    dismissalPolicy: .immediate
                )
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
