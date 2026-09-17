import ActivityKit
import SwiftUI
import WidgetKit

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

@main
struct TriLoopLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TriLoopWorkoutLiveActivity()
    }
}

struct TriLoopWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.disciplineName, systemImage: "figure.run")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state, compact: true)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.stepTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.stepPosition)
                        if let repetition = context.state.repetition {
                            Text("·")
                            Text(repetition)
                        }
                        Spacer()
                        if context.state.isPaused {
                            Label("Paused", systemImage: "pause.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            } compactTrailing: {
                timer(context.state, compact: true)
                    .frame(maxWidth: 58)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.run.circle.fill")
                .font(.title2)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.stepTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(context.state.stepPosition)
                    if let repetition = context.state.repetition {
                        Text("·")
                        Text(repetition)
                    }
                    if context.state.isPaused {
                        Text("· Paused")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            timer(context.state, compact: false)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func timer(_ state: WorkoutActivityAttributes.ContentState, compact: Bool) -> some View {
        if state.isPaused {
            Text(format(state.frozenSeconds))
                .monospacedDigit()
        } else if state.isCountdown, let end = state.timerEndsAt {
            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true, showsHours: !compact)
                .monospacedDigit()
        } else if let start = state.timerStartedAt {
            Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: !compact)
                .monospacedDigit()
        } else {
            Text(format(state.frozenSeconds))
                .monospacedDigit()
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}