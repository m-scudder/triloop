import SwiftUI

/// Which days are training days. Everything not picked is a rest day, which is
/// a more honest question than "how many rest days do you want?" — Sunday off
/// and Wednesday off produce very different weeks.
struct TrainingDaysStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(
                title: "When can you train?"
            )

            HStack(spacing: 6) {
                ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                    dayChip(weekday)
                }
            }

            LabeledContent("Weekly commitment", value: "About \(TrainingFormatter.totalDuration(seconds: TimeInterval(model.setup.preferences.reduce(0) { $0 + $1.sessionsPerWeek * $1.typicalMinutes } * 60)))")
            Text("Requested time; your preview shows what fits.")
                .font(.caption).foregroundStyle(.secondary)

            DisclosureGroup("Adjust commitment") {
                ForEach(model.setup.preferences, id: \.sport) { preference in
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper("\(preference.sport.displayName): \(preference.sessionsPerWeek) / week", value: Binding(
                            get: { preference.sessionsPerWeek },
                            set: { model.setSessions($0, for: preference.sport) }
                        ), in: SportPreference.permittedSessions)
                        if preference.isTrained {
                            Picker("Time per session", selection: Binding(
                                get: { preference.typicalMinutes },
                                set: { model.setTypicalMinutes($0, for: preference.sport) }
                            )) {
                                ForEach(Array(Set([20, 30, 45, 60, 75, 90, preference.typicalMinutes])).sorted(), id: \.self) { minutes in
                                    Text("\(minutes) min").tag(minutes)
                                }
                            }
                        }
                    }.padding(.vertical, 8)
                }
            }

            DisclosureGroup("Time available each day") {

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
            if !model.setup.preferences.contains(where: \.isTrained) {
                Text("Choose at least one sport in Adjust commitment.")
                    .font(.footnote).foregroundStyle(.orange)
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
                subtitle: "A starting point, not a promise. Athevia schedules fewer sessions when the week cannot hold them, and holds a sport back when you need to recover."
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
