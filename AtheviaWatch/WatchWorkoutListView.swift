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
                    }
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
            Image(systemName: workout.discipline.symbolName)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(workout.title)
                        .font(.headline)
                        .lineLimit(1)
                    if workout.status == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
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
