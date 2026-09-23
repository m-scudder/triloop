import SwiftUI

struct WatchWorkoutDetailView: View {
    let workout: WatchWorkoutPayload

    @EnvironmentObject private var manager: WatchWorkoutSessionManager
    @EnvironmentObject private var store: WatchWorkoutStore
    @State private var startConfiguration: WatchWorkoutStartConfiguration
    @State private var isStarting = false
    @State private var showsPlayer = false

    init(workout: WatchWorkoutPayload) {
        self.workout = workout
        _startConfiguration = State(
            initialValue: .defaultValue(for: workout.discipline)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if !workout.goal.isEmpty {
                    Text(workout.goal)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !workout.steps.isEmpty {
                    Divider()
                    Text("Workout")
                        .font(.headline)

                    ForEach(workout.steps) { step in
                        WatchWorkoutStepView(step: step)
                    }
                }

                if !isCompleted && !isCurrentWorkout {
                    NavigationLink {
                        WatchWorkoutSetupView(
                            workout: workout,
                            configuration: $startConfiguration
                        )
                    } label: {
                        HStack {
                            Label(
                                startConfiguration.displayName,
                                systemImage: "slider.horizontal.3"
                            )
                            Spacer()
                        }
                    }
                }

                Button(action: startOrResume) {
                    HStack {
                        if isStarting || manager.state == .preparing {
                            ProgressView()
                        } else {
                            Image(
                                systemName: isCompleted
                                    ? "checkmark.circle.fill"
                                    : (isCurrentWorkout ? "play.fill" : "figure.run")
                            )
                        }

                        Text(buttonTitle)
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(
                    isCompleted
                    || isStarting
                    || workout.status == .skipped
                    || (manager.isActive && !isCurrentWorkout)
                )

                if isCompleted {
                    Text("This workout is complete and can’t be started again.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(workout.discipline.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsPlayer) {
            WatchWorkoutPlayerView(workout: workout)
        }
        .alert(
            "Workout",
            isPresented: Binding(
                get: { manager.errorMessage != nil },
                set: { if !$0 { manager.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                manager.clearError()
            }
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }

    private var isCurrentWorkout: Bool {
        manager.activeWorkout?.id == workout.id && manager.isActive
    }

    private var isCompleted: Bool {
        store.isCompleted(workout)
            || manager.completedPlannedWorkoutID == workout.id
    }

    private var buttonTitle: String {
        if isCompleted {
            return "Workout Completed"
        }
        return isCurrentWorkout ? "Resume Workout" : "Start Workout"
    }

    private func startOrResume() {
        guard !isCompleted else { return }

        if isCurrentWorkout {
            showsPlayer = true
            return
        }

        isStarting = true
        Task { @MainActor in
            let started = await manager.start(
                workout,
                configuration: startConfiguration,
                coaching: store.coachingSettings
            )
            isStarting = false
            if started {
                showsPlayer = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: workout.discipline.symbolName)
                .font(.title2)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(workout.discipline.sportTint)

            Text(workout.title)
                .font(.title3.weight(.semibold))

            HStack(spacing: 6) {
                if let duration = workout.estimatedDurationSeconds {
                    Label(duration.atheviaWatchDurationText, systemImage: "clock")
                }
                if let distance = workout.estimatedDistanceMeters {
                    Label(distance.atheviaWatchDistanceText, systemImage: "ruler")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct WatchWorkoutSetupView: View {
    let workout: WatchWorkoutPayload
    @Binding var configuration: WatchWorkoutStartConfiguration

    var body: some View {
        Form {
            switch workout.discipline {
            case .running, .cycling:
                Picker("Workout Type", selection: $configuration.environment) {
                    Text("Outdoor")
                        .tag(WatchWorkoutStartConfiguration.Environment.outdoor)
                    Text("Indoor")
                        .tag(WatchWorkoutStartConfiguration.Environment.indoor)
                }

            case .swimming:
                Picker("Swim Type", selection: $configuration.environment) {
                    Text("Pool")
                        .tag(WatchWorkoutStartConfiguration.Environment.pool)
                    Text("Open Water")
                        .tag(WatchWorkoutStartConfiguration.Environment.openWater)
                }

                if configuration.environment == .pool {
                    Picker(
                        "Pool Length",
                        selection: Binding(
                            get: { configuration.poolLengthMeters ?? 25 },
                            set: { configuration.poolLengthMeters = $0 }
                        )
                    ) {
                        Text("20 m").tag(20.0)
                        Text("25 m").tag(25.0)
                        Text("33.3 m").tag(33.3)
                        Text("50 m").tag(50.0)
                    }
                }
            }
        }
        .navigationTitle("Workout Setup")
    }
}

private struct WatchWorkoutStepView: View {
    let step: WatchWorkoutStepPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(stepTitle)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if let prescription {
                    Text(prescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let intensity = step.targetIntensity {
                Text(intensity.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let instructions = step.instructions, !instructions.isEmpty {
                Text(instructions)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if step.kind == .repeatBlock {
                ForEach(step.children) { child in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(child.title)
                                .font(.caption)

                            if let value = prescription(for: child) {
                                Text(value)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 6)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var stepTitle: String {
        if step.kind == .repeatBlock, let repeatCount = step.repeatCount {
            return "\(repeatCount)× \(step.title)"
        }
        return step.title
    }

    private var prescription: String? {
        prescription(for: step)
    }

    private func prescription(for step: WatchWorkoutStepPayload) -> String? {
        if let duration = step.durationSeconds {
            return duration.atheviaWatchDurationText
        }
        if let distance = step.distanceMeters {
            return distance.atheviaWatchDistanceText
        }
        return nil
    }
}
