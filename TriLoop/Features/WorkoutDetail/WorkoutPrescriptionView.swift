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
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: sectionTitle)

            Card {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.title)
                        .font(.body.weight(.medium))
                    Spacer(minLength: 12)
                    if let measure = measureText {
                        Text(measure)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let instructions = step.instructions {
                Text(instructions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var repeatBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: "Main set")

            Card(padding: 0) {
                VStack(spacing: 0) {
                    Text("Repeat \(step.repeatCount ?? 1) times")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    Divider()

                    ForEach(step.orderedChildren, id: \.id) { child in
                        HStack(alignment: .firstTextBaseline) {
                            if let seconds = child.durationSeconds {
                                Text(TrainingFormatter.intervalDuration(seconds: seconds))
                                    .font(.body.weight(.medium))
                                    .monospacedDigit()
                            } else if let meters = child.distanceMeters {
                                Text(TrainingFormatter.distance(meters: meters))
                                    .font(.body.weight(.medium))
                                    .monospacedDigit()
                            }

                            Text(child.title)
                                .font(.body)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 12)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if child.id != step.orderedChildren.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }

            if let instructions = step.instructions {
                Text(instructions)
                    .font(.footnote)
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
