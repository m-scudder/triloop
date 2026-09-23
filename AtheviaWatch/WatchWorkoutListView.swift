import SwiftUI

struct WatchWorkoutListView: View {
    @EnvironmentObject private var store: WatchWorkoutStore
    @EnvironmentObject private var manager: WatchWorkoutSessionManager

    var body: some View {
        NavigationStack {
            Group {
                if store.workouts.isEmpty && manager.activeWorkout == nil {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.run.circle",
                        description: Text("Open Athevia on your iPhone to sync your current training week.")
                    )
                } else {
                    List {
                        if let active = manager.activeWorkout, manager.isActive {
                            Section("Active Workout") {
                                NavigationLink {
                                    WatchWorkoutPlayerView(workout: active)
                                } label: {
                                    WatchWorkoutRow(
                                        workout: active,
                                        isCompleted: false,
                                        showsActiveIndicator: true
                                    )
                                }
                                .listRowBackground(
                                    active.discipline.sportTint.opacity(0.24)
                                )
                            }
                        }

                        if !todayWorkouts.isEmpty {
                            Section("Today") {
                                ForEach(todayWorkouts) { workout in
                                    workoutLink(workout)
                                }
                            }
                        }

                        if !weekWorkouts.isEmpty {
                            Section("This Week") {
                                ForEach(weekWorkouts) { workout in
                                    workoutLink(workout)
                                }
                            }
                        }

                        if !completedWorkouts.isEmpty {
                            Section("Completed") {
                                ForEach(completedWorkouts) { workout in
                                    workoutLink(workout)
                                }
                            }
                        }
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

    private var activeWorkoutID: UUID? {
        manager.isActive ? manager.activeWorkout?.id : nil
    }

    private var incompleteWorkouts: [WatchWorkoutPayload] {
        store.workouts.filter {
            !store.isCompleted($0) && $0.id != activeWorkoutID
        }
    }

    private var todayWorkouts: [WatchWorkoutPayload] {
        incompleteWorkouts.filter {
            Calendar.current.isDateInToday($0.date)
        }
    }

    private var weekWorkouts: [WatchWorkoutPayload] {
        incompleteWorkouts.filter {
            !Calendar.current.isDateInToday($0.date)
        }
    }

    private var completedWorkouts: [WatchWorkoutPayload] {
        store.workouts.filter {
            store.isCompleted($0) && $0.id != activeWorkoutID
        }
    }

    private func workoutLink(_ workout: WatchWorkoutPayload) -> some View {
        NavigationLink(value: workout.id) {
            WatchWorkoutRow(
                workout: workout,
                isCompleted: store.isCompleted(workout),
                showsActiveIndicator: false
            )
        }
        .listRowBackground(
            workout.discipline.sportTint.opacity(
                store.isCompleted(workout) ? 0.09 : 0.16
            )
        )
    }
}

private struct WatchWorkoutRow: View {
    let workout: WatchWorkoutPayload
    let isCompleted: Bool
    let showsActiveIndicator: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(workout.discipline.sportTint.opacity(0.22))

                Image(systemName: workout.discipline.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(workout.discipline.sportTint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(workout.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if showsActiveIndicator {
                        Image(systemName: "record.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Text(showsActiveIndicator ? "In Progress" : subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        showsActiveIndicator ? Color.green : Color.secondary
                    )
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .opacity(isCompleted ? 0.72 : 1)
    }

    private var subtitle: String {
        var values = [
            workout.date.formatted(
                .dateTime
                    .weekday(.abbreviated)
                    .day()
                    .month(.abbreviated)
            )
        ]
        if let duration = workout.estimatedDurationSeconds {
            values.append(duration.atheviaWatchDurationText)
        } else if let distance = workout.estimatedDistanceMeters {
            values.append(distance.atheviaWatchDistanceText)
        }
        return values.joined(separator: " · ")
    }
}


extension WatchWorkoutDiscipline {
    var sportTint: Color {
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
