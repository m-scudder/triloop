import SwiftUI

/// Collects the remaining plan inputs in one place: intent, available days,
/// and the time ceiling that applies to each selected training day.
struct TrainingDaysStepView: View {
    @Bindable var model: OnboardingModel

    private let durationOptions = [30, 45, 60, 90, 120]
    private let objectiveColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(title: "Build around your week")

            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Goal")

                LazyVGrid(columns: objectiveColumns, spacing: 8) {
                    ForEach(TrainingObjectiveKind.allCases, id: \.self) { kind in
                        AtheviaChoiceChip(
                            title: kind.displayName,
                            isSelected: model.setup.objective.kind == kind
                        ) {
                            model.choose(objectiveKind: kind)
                        }
                        .accessibilityIdentifier("objective.\(kind.rawValue)")
                    }
                }

                if model.setup.objective.kind == .event {
                    EventGoalFields(
                        objective: model.setup.objective,
                        selectedSports: model.selectedSports,
                        minimumDate: model.minimumStartDate,
                        showsTargetIntent: true,
                        onChange: model.choose(objective:)
                    )
                    .padding(.top, 4)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Days you can train")

                HStack(spacing: 6) {
                    ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                        dayChip(weekday)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Time per training day")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 8
                ) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        durationChip(minutes)
                    }
                }
            }

            if model.canChooseStartDate {
                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(text: "Start training")

                    DatePicker(
                        "Start date",
                        selection: Binding(
                            get: { model.selectedStartDate },
                            set: { model.choose(startDate: $0) }
                        ),
                        in: model.minimumStartDate...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                }
            }

            if model.setup.schedule.availableDays.count < model.minimumTrainingDays {
                Label(
                    "Choose at least \(model.minimumTrainingDays) training days.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if model.sharedTrainingMinutes == nil {
                Label("Choose your training time.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dayChip(_ weekday: Weekday) -> some View {
        let isOn = model.setup.schedule.isAvailable(on: weekday)

        return Button {
            model.toggleDay(weekday)
        } label: {
            Text(weekday.initial)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.fill.tertiary))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator, lineWidth: isOn ? 0 : 0.5)
                )
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekday.displayName)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func durationChip(_ minutes: Int) -> some View {
        AtheviaChoiceChip(
            title: "\(minutes) min",
            isSelected: model.sharedTrainingMinutes == minutes
        ) {
            model.setSharedMaxDuration(minutes)
        }
    }
}
