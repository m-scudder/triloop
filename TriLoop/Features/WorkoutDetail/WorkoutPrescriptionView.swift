import SwiftData
import SwiftUI

/// Renders a workout's prescription. Shared by Today's card and Workout Detail
/// so the two can never drift apart.
struct WorkoutPrescriptionView: View {
    let workout: PlannedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(workout.orderedSteps, id: \.id) { step in
                StepView(step: step)
            }
        }
    }
}

private struct StepView: View {
    let step: WorkoutStep

    var body: some View {
        if step.kind == .repeatBlock {
            repeatBlock
        } else {
            simpleStep
        }
    }

    private var simpleStep: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(step.title)
                    .font(.title3.weight(.medium))
                if let measure = measureText {
                    Text(measure)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            if let instructions = step.instructions {
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var repeatBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(step.repeatCount ?? 1) rounds")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(step.orderedChildren, id: \.id) { child in
                    HStack(alignment: .firstTextBaseline) {
                        Text(child.title)
                            .font(.title3.weight(.medium))
                        Spacer(minLength: 12)
                        if let seconds = child.durationSeconds {
                            Text(TrainingFormatter.intervalDuration(seconds: seconds))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else if let meters = child.distanceMeters {
                            Text(TrainingFormatter.distance(meters: meters))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))

            if let instructions = step.instructions {
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sectionTitle: String {
        switch step.kind {
        case .warmUp: "Warm-up"
        case .work: "Main set"
        case .recovery: "Recovery"
        case .cooldown: "Cooldown"
        case .repeatBlock: "Intervals"
        }
    }

    private var measureText: String? {
        if let seconds = step.durationSeconds {
            return TrainingFormatter.totalDuration(seconds: seconds)
        }
        if let meters = step.distanceMeters {
            return TrainingFormatter.distance(meters: meters)
        }
        return nil
    }
}

#Preview("Running") {
    ScrollView {
        WorkoutPrescriptionView(workout: PreviewData.workout(.running))
            .padding()
    }
    .modelContainer(PreviewData.container)
}

#Preview("Swimming") {
    ScrollView {
        WorkoutPrescriptionView(workout: PreviewData.workout(.swimming))
            .padding()
    }
    .modelContainer(PreviewData.container)
}
