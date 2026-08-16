import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    let workout: PlannedWorkout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if !workout.goal.isEmpty {
                    LabeledSection(title: "Purpose") {
                        Text(workout.goal)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                if workout.orderedSteps.isEmpty {
                    Text("No session today. Rest is part of the plan.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    WorkoutPrescriptionView(workout: workout)
                }

                if let rpe = workout.targetRPE {
                    LabeledSection(title: "Target effort") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TrainingFormatter.rpe(rpe))
                                .font(.title3.weight(.medium))
                            Text(RPEScale.label(for: rpe.lower))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Phase 6 replaces this with WorkoutKit scheduling.
                Button {
                } label: {
                    Label("Add to Apple Watch", systemImage: "applewatch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
                .opacity(workout.discipline.isTrainingSession ? 1 : 0)
            }
            .padding(20)
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisciplineBadge(discipline: workout.discipline, size: 52)

            Text(workout.title)
                .font(.largeTitle.weight(.semibold))

            HStack(spacing: 6) {
                Text(workout.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                if let summary = WorkoutSummaryText.make(for: workout) {
                    Text("·")
                    Text(summary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

struct LabeledSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(workout: PreviewData.workout(.running))
    }
    .modelContainer(PreviewData.container)
}
