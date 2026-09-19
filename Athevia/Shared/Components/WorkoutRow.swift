import SwiftUI

/// One-line summary of a workout's prescribed volume, e.g. "28 min" or "300 m".
struct WorkoutSummaryText {
    static func make(for workout: PlannedWorkout) -> String? {
        if workout.discipline == .swimming, let distance = workout.estimatedDistanceMeters {
            return TrainingFormatter.distance(meters: distance)
        }
        if let duration = workout.estimatedDurationSeconds {
            return TrainingFormatter.totalDuration(seconds: duration)
        }
        if let distance = workout.estimatedDistanceMeters {
            return TrainingFormatter.distance(meters: distance)
        }
        return nil
    }
}

struct WorkoutRow: View {
    let workout: PlannedWorkout
    var isToday: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(TrainingFormatter.weekdayAbbreviation(for: workout.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                Text(workout.date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
            }
            .frame(width: 34)

            DisciplineBadge(discipline: workout.discipline, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let summary = WorkoutSummaryText.make(for: workout) {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if workout.awaitingFeedback {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            } else if workout.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            } else if isToday {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [workout.date.formatted(.dateTime.weekday(.wide)), workout.title]
        if let summary = WorkoutSummaryText.make(for: workout) { parts.append(summary) }
        if isToday { parts.append("Today") }
        if workout.awaitingFeedback {
            parts.append("Completed, needs feedback")
        } else if workout.status == .completed {
            parts.append("Completed")
        }
        return parts.joined(separator: ", ")
    }
}
