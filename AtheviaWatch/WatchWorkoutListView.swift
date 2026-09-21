import SwiftUI

struct WatchWorkoutListView: View {
    @EnvironmentObject private var store: WatchWorkoutStore

    var body: some View {
        NavigationStack {
            Group {
                if store.workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.run.circle",
                        description: Text("Open Athevia on your iPhone to sync your current training week.")
                    )
                } else {
                    List(store.workouts) { workout in
                        NavigationLink(value: workout.id) {
                            WatchWorkoutRow(workout: workout)
                        }
                        .listRowBackground(
                            workout.discipline.listTint.opacity(0.16)
                        )
                    }
                    .listStyle(.carousel)
                    .navigationDestination(for: UUID.self) { id in
                        if let workout = store.workouts.first(where: { $0.id == id }) {
                            WatchWorkoutDetailView(workout: workout)
                        }
                    }
                }
            }
            .navigationTitle("Workouts")
        }
    }
}

private struct WatchWorkoutRow: View {
    let workout: WatchWorkoutPayload

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(workout.discipline.listTint.opacity(0.22))

                Image(systemName: workout.discipline.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(workout.discipline.listTint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(workout.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if workout.status == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(workout.discipline.listTint)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        var values = [workout.date.formatted(.dateTime.weekday(.abbreviated))]
        if let duration = workout.estimatedDurationSeconds {
            values.append(duration.atheviaWatchDurationText)
        } else if let distance = workout.estimatedDistanceMeters {
            values.append(distance.atheviaWatchDistanceText)
        }
        return values.joined(separator: " · ")
    }
}

private extension WatchWorkoutDiscipline {
    var listTint: Color {
        switch self {
        case .running:
            .orange
        case .cycling:
            .green
        case .swimming:
            .blue
        }
    }
}
