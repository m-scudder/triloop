import SwiftData
import SwiftUI

struct TodayView: View {
    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.first {
                    content(for: plan)
                } else {
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "calendar",
                        description: Text("Your first training week has not been generated.")
                    )
                }
            }
            .navigationTitle("TriLoop")
        }
    }

    private func content(for plan: WeeklyPlan) -> some View {
        let focus = TodayFocus.resolve(plan: plan)
        let focusedWorkout = focus.workoutID.flatMap { id in
            plan.orderedWorkouts.first { $0.id == id }
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Greeting.text())
                        .font(.title2.weight(.semibold))
                    Text(subtitle(plan: plan, focus: focus))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                if let workout = focusedWorkout {
                    FocusWorkoutCard(workout: workout, kind: focus.kind)
                } else {
                    Text("This week is complete. Generate the next one when you're ready.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                LabeledSection(title: "This week") {
                    VStack(spacing: 0) {
                        ForEach(plan.orderedWorkouts, id: \.id) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                WorkoutRow(workout: workout, isToday: workout.id == focusedWorkout?.id && focus.kind == .today)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 6)

                            if workout.id != plan.orderedWorkouts.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func subtitle(plan: WeeklyPlan, focus: TodayFocus) -> String {
        guard let dayNumber = focus.dayNumber else {
            return "Week \(plan.weekNumber)"
        }
        return "Week \(plan.weekNumber) · Day \(dayNumber)"
    }
}

private struct FocusWorkoutCard: View {
    let workout: PlannedWorkout
    let kind: TodayFocus.Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(headline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 14) {
                DisciplineBadge(discipline: workout.discipline, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.title2.weight(.semibold))
                    if let summary = WorkoutSummaryText.make(for: workout) {
                        Text(summary)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let intervals = intervalSummary {
                Text(intervals)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let rpe = workout.targetRPE {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target effort")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(TrainingFormatter.rpe(rpe))
                        .font(.body.weight(.medium))
                }
            }

            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                Text("View workout")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quinary, in: .rect(cornerRadius: 16))
    }

    private var headline: String {
        switch kind {
        case .today: "Today"
        case .upcoming: "Up next · \(workout.date.formatted(.dateTime.weekday(.wide)))"
        case .weekComplete: "Week complete"
        }
    }

    /// Compact interval preview, e.g. "6 × 1:00 run / 2:00 walk".
    private var intervalSummary: String? {
        guard let block = workout.orderedSteps.first(where: { $0.kind == .repeatBlock }),
              let count = block.repeatCount else { return nil }
        let parts = block.orderedChildren.compactMap { child -> String? in
            guard let seconds = child.durationSeconds else { return nil }
            return "\(TrainingFormatter.intervalDuration(seconds: seconds)) \(child.title.lowercased())"
        }
        guard !parts.isEmpty else { return nil }
        return "\(count) × " + parts.joined(separator: " / ")
    }
}

#Preview {
    TodayView()
        .modelContainer(PreviewData.container)
}
