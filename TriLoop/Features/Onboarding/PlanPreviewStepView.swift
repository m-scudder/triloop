import SwiftUI

/// The generated week, shown before it becomes the athlete's plan.
///
/// Nothing is committed until "Start This Plan": a preview the athlete cannot
/// refuse is not a preview.
struct PlanPreviewStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(
            primaryTitle: model.isUpgrade ? "Start This Week" : "Start This Plan",
            isPrimaryEnabled: model.preview != nil && !model.isWorking,
            secondary: OnboardingSecondaryAction("Adjust Days") {
                model.jump(to: .days)
            },
            primary: model.start
        ) {
            OnboardingHeader(
                title: model.isUpgrade ? "Your next week" : "Your first week",
                subtitle: model.preview.map(startLine) ?? model.failure
            )

            if let failure = model.failure {
                ContentUnavailableView(
                    "This week could not be built",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(failure)
                )
            } else if let plan = model.preview {
                if model.canStartNow {
                    startPicker
                }

                week(plan)

                Text(plan.generationReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Your first week starts conservatively so TriLoop can understand how you respond to each discipline. Future weeks adapt based on completion, effort, pain and recovery.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
    }

    /// Starting today gives a short week rather than backdating sessions the
    /// athlete never had the chance to do.
    private var startPicker: some View {
        Picker("Start", selection: Binding(
            get: { model.startChoice },
            set: { model.choose(start: $0) }
        )) {
            Text("Start today").tag(OnboardingModel.StartChoice.now)
            Text("Start Monday").tag(OnboardingModel.StartChoice.nextMonday)
        }
        .pickerStyle(.segmented)
    }

    /// Training weeks end on a Sunday, so starting mid-week gives a short first
    /// week rather than backdating sessions the athlete never had.
    private func startLine(_ plan: WeeklyPlan) -> String {
        let calendar = Calendar.current
        let days = (calendar.dateComponents([.day], from: plan.startDate, to: plan.endDate).day ?? 6) + 1

        let opening = calendar.isDateInToday(plan.startDate)
            ? "Starting today"
            : "Starting \(plan.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))"

        return days < 7 ? "\(opening) · \(days) days to Sunday" : opening
    }

    private func week(_ plan: WeeklyPlan) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(plan.orderedWorkouts, id: \.id) { workout in
                    row(workout)

                    if workout.id != plan.orderedWorkouts.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
        }
    }

    private func row(_ workout: PlannedWorkout) -> some View {
        HStack(spacing: 12) {
            DisciplineBadge(discipline: workout.discipline, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(weekday(of: workout.date))
                    .font(.subheadline.weight(.medium))
                Text(detail(workout))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func weekday(of date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private func detail(_ workout: PlannedWorkout) -> String {
        guard workout.discipline.isTrainingSession else { return workout.title }

        if let summary = WorkoutSummaryText.make(for: workout) {
            return "\(workout.title) · \(summary)"
        }
        return workout.title
    }
}
