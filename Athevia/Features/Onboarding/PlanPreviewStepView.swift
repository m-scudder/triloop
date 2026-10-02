import SwiftUI

/// The generated week, shown before it becomes the athlete's plan.
///
/// Nothing is committed until "Start My Plan": a preview the athlete cannot
/// refuse is not a preview.
struct PlanPreviewStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(
            primaryTitle: "Start My Plan",
            isPrimaryEnabled: model.preview != nil && !model.isWorking,
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
                if model.setup.objective.kind == .event,
                   model.setup.objective.event?.eventDate != nil {
                    racePlanHeader(plan)
                }

                week(plan)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
        .task { if model.preview == nil { model.buildPreview() } }
    }

    @ViewBuilder
    private func racePlanHeader(_ plan: WeeklyPlan) -> some View {
        if let event = model.setup.objective.event,
           let eventDate = event.eventDate {
            NavigationLink {
                FullTrainingJourneyView(
                    setup: model.setup,
                    plans: [plan]
                )
            } label: {
                Card {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface))
                                .frame(width: 42, height: 42)

                            Image(systemName: "flag.checkered")
                                .font(.subheadline.weight(.semibold))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(TrainingFormatter.shortDate(eventDate, includeYear: true))
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        }

                        Spacer(minLength: 8)

                        if let weeks = event.weeksRemaining() {
                            Text("\(weeks) wk")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Race plan for \(event.displayName)")
        }
    }

    /// Weeks always run Monday to Sunday, so the useful thing to state is when
    /// the athlete actually trains, not when the plan's calendar week opens.
    private func startLine(_ plan: WeeklyPlan) -> String {
        let calendar = Calendar.current
        guard let first = plan.trainingSessions.map(\.date).min() else {
            return "No sessions scheduled"
        }

        if calendar.isDateInToday(first) { return "First session today" }
        if calendar.isDateInTomorrow(first) { return "First session tomorrow" }
        return "First session \(TrainingFormatter.shortDate(first))"
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
                Text(dayAndDate(of: workout.date))
                    .font(.subheadline.weight(.medium))
                Text(detail(workout))
                    .font(.caption)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func dayAndDate(of date: Date) -> String {
        TrainingFormatter.shortDate(date)
    }

    private func detail(_ workout: PlannedWorkout) -> String {
        guard workout.discipline.isTrainingSession else { return workout.title }

        if let summary = WorkoutSummaryText.make(for: workout) {
            return "\(workout.title) · \(summary)"
        }
        return workout.title
    }
}

