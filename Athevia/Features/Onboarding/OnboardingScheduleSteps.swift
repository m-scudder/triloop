import SwiftUI

/// Training availability stays intentionally small: choose the days once and
/// one time window that applies to every selected training day.
struct TrainingDaysStepView: View {
    @Bindable var model: OnboardingModel

    private let durationOptions = [30, 45, 60, 90, 120]

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(title: "When can you train?")

            HStack(spacing: 6) {
                ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                    dayChip(weekday)
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

            Text("Athevia assigns sessions automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                        .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary))
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
        let isSelected = model.sharedTrainingMinutes == minutes

        return Button {
            model.setSharedMaxDuration(minutes)
        } label: {
            Text("\(minutes) min")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary))
                )
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
