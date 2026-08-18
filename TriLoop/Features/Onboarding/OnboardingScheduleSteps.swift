import SwiftUI

/// Which days are training days. Everything not picked is a rest day, which is
/// a more honest question than "how many rest days do you want?" — Sunday off
/// and Wednesday off produce very different weeks.
struct TrainingDaysStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(
                title: "Which days can you train?",
                subtitle: "Pick the days that are usually free. The rest become recovery days, and TriLoop will not fill every day you offer."
            )

            HStack(spacing: 6) {
                ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                    dayChip(weekday)
                }
            }

            if !model.setup.schedule.restDays.isEmpty {
                Text(restSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Time on each day")

                ForEach(model.setup.schedule.availableDays, id: \.weekday) { day in
                    HStack {
                        Text(day.weekday.displayName)
                            .font(.subheadline)

                        Spacer()

                        Picker("Time available", selection: Binding(
                            get: { day.maxDurationMinutes ?? 0 },
                            set: { model.setMaxDuration($0 == 0 ? nil : $0, on: day.weekday) }
                        )) {
                            Text("No limit").tag(0)
                            ForEach([30, 45, 60, 90, 120], id: \.self) { option in
                                Text("\(option) min").tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }

            if !model.setup.schedule.isUsable {
                Label("Choose at least two days.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var restSummary: String {
        let names = model.setup.schedule.restDays.map(\.displayName)
        guard names.count < 7 else { return "No training days chosen yet." }
        return "Rest: \(names.joined(separator: ", "))"
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
                        .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
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
}

/// How much of each sport the athlete wants, and how long a session runs.
struct CommitmentStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(
                title: "How much of each sport?",
                subtitle: "A starting point, not a promise. TriLoop schedules fewer sessions when the week cannot hold them, and holds a sport back when you need to recover."
            )

            ForEach(model.setup.preferences, id: \.sport) { preference in
                sportCard(preference)
            }

            if !model.setup.preferences.contains(where: \.isTrained) {
                Label("Pick at least one sport.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sportCard(_ preference: SportPreference) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: preference.sport.discipline.symbolName)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(preference.sport.discipline.gradient, in: .rect(cornerRadius: 9))
                    Text(preference.sport.displayName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }

                HStack {
                    Text("Times a week")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Times a week", selection: Binding(
                        get: { preference.sessionsPerWeek },
                        set: { model.setSessions($0, for: preference.sport) }
                    )) {
                        Text("Not yet").tag(0)
                        ForEach(1...SportPreference.permittedSessions.upperBound, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                if preference.isTrained {
                    HStack {
                        Text("Typical session")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Typical session", selection: Binding(
                            get: { preference.typicalMinutes },
                            set: { model.setTypicalMinutes($0, for: preference.sport) }
                        )) {
                            ForEach([30, 45, 60, 90], id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }
        }
    }
}
