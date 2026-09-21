import SwiftUI

struct WatchWorkoutDetailView: View {
    let workout: WatchWorkoutPayload

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

                Button("Start Workout") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)

                Text("Native workout execution is added in Phase W2. The full workout is already cached on this Watch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(workout.discipline.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: workout.discipline.symbolName)
                .font(.title2)

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
