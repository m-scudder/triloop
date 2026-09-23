import SwiftUI

struct StartingPointStepView: View {
    @Bindable var model: OnboardingModel
    @State private var expandedSport: Sport?
    @State private var poolText = ""
    @State private var customPoolSelected = false
    @FocusState private var isEditingPool: Bool

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(
                title: "Where are you starting?",
                subtitle: "Choose your sports, then set your current starting point."
            )

            VStack(spacing: 12) {
                ForEach(Sport.allCases, id: \.self) { sport in
                    sportCard(sport)
                }
            }

            if model.selectedSports.isEmpty {
                Label("Select at least one sport.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if model.isSportSelected(.swimming),
                      !PoolLength.isValid(model.poolLengthMeters) {
                Label("Choose a pool length.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func sportCard(_ sport: Sport) -> some View {
        let selected = model.isSportSelected(sport)
        let expanded = selected && expandedSport == sport

        VStack(spacing: 0) {
            Button {
                if selected {
                    model.toggleSport(sport)
                    if expandedSport == sport {
                        expandedSport = nil
                    }
                } else {
                    model.toggleSport(sport)
                    prepareDetails(for: sport)
                    expandedSport = sport
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? sport.discipline.tint : .secondary)

                    DisciplineBadge(discipline: sport.discipline, size: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(sport.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(selected ? summary(sport) : "Tap to include")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if selected {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .contentShape(.rect)
                            .onTapGesture {
                                if expanded {
                                    expandedSport = nil
                                } else {
                                    prepareDetails(for: sport)
                                    expandedSport = sport
                                }
                            }
                    }
                }
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("startingPoint.\(sport.rawValue)")
            .accessibilityLabel("\(sport.displayName), \(selected ? "selected" : "not selected")")
            .accessibilityAddTraits(selected ? [.isSelected] : [])

            if expanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow(text: "Starting point")
                    baselineChoices(sport)

                    Button(notSureTitle(for: sport)) {
                        chooseConservativeDefault(for: sport)
                    }
                    .font(.subheadline.weight(.medium))

                    if sport == .swimming {
                        swimmingDetails
                    }
                }
                .padding(14)
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    selected ? sport.discipline.tint.opacity(0.75) : Color.secondary.opacity(0.18),
                    lineWidth: selected ? 1.5 : 0.5
                )
        )
    }

    @ViewBuilder
    private var swimmingDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Primary stroke")

            Picker(
                "Primary stroke",
                selection: Binding(
                    get: { model.setup.baseline.stroke },
                    set: { model.choose(stroke: $0) }
                )
            ) {
                ForEach(SwimStroke.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }
            .pickerStyle(.segmented)

            SectionEyebrow(text: "Pool length")

            HStack(spacing: 8) {
                poolChoice("25 m", meters: 25)
                poolChoice("50 m", meters: 50)

                Button {
                    customPoolSelected.toggle()
                    poolText = ""
                    model.setPoolLength(customPoolSelected ? 0 : 25)
                    isEditingPool = customPoolSelected
                } label: {
                    compactChoice("Other", selected: customPoolSelected)
                }
                .buttonStyle(.plain)
            }

            if customPoolSelected {
                TextField("Pool length in metres", text: $poolText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditingPool)
                    .onChange(of: poolText) { _, value in
                        let metres = (try? Double(value, format: .number)) ?? 0
                        model.setPoolLength(PoolLength.isValid(metres) ? metres : 0)
                    }

                if !poolText.isEmpty,
                   !PoolLength.isValid(model.poolLengthMeters) {
                    Text("Enter a length between \(Int(PoolLength.permittedRange.lowerBound)) and \(Int(PoolLength.permittedRange.upperBound)) metres.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func baselineChoices(_ sport: Sport) -> some View {
        VStack(spacing: 8) {
            switch sport {
            case .running:
                ForEach(RunningBaseline.allCases, id: \.self) { baseline in
                    baselineChoice(
                        baseline.displayName,
                        selected: model.setup.baseline.running == baseline
                    ) {
                        model.choose(running: baseline)
                    }
                }

            case .swimming:
                ForEach(SwimmingBaseline.allCases, id: \.self) { baseline in
                    baselineChoice(
                        baseline.displayName,
                        selected: model.setup.baseline.swimming == baseline
                    ) {
                        model.choose(swimming: baseline)
                    }
                }

            case .cycling:
                ForEach(CyclingBaseline.allCases, id: \.self) { baseline in
                    baselineChoice(
                        baseline.displayName,
                        selected: model.setup.baseline.cycling == baseline
                    ) {
                        model.choose(cycling: baseline)
                    }
                }
            }
        }
    }

    private func baselineChoice(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                selected ? Color.accentColor.opacity(0.10) : Color.clear,
                in: .rect(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func poolChoice(_ title: String, meters: Double) -> some View {
        let selected = !customPoolSelected && model.poolLengthMeters == meters

        return Button {
            customPoolSelected = false
            isEditingPool = false
            poolText = ""
            model.setPoolLength(meters)
        } label: {
            compactChoice(title, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func compactChoice(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                selected ? Color.accentColor : Color.secondary.opacity(0.10),
                in: .rect(cornerRadius: 10)
            )
    }

    private func prepareDetails(for sport: Sport) {
        guard sport == .swimming else {
            customPoolSelected = false
            poolText = ""
            return
        }

        customPoolSelected = PoolLength.isValid(model.poolLengthMeters)
            && model.poolLengthMeters != 25
            && model.poolLengthMeters != 50
        poolText = customPoolSelected
            ? model.poolLengthMeters.formatted(.number)
            : ""
    }

    private func notSureTitle(for sport: Sport) -> String {
        switch sport {
        case .running:
            "Not sure — start with run/walk"
        case .swimming:
            "Not sure — start with supported practice"
        case .cycling:
            "Not sure — start with a short ride"
        }
    }

    private func chooseConservativeDefault(for sport: Sport) {
        switch sport {
        case .running:
            model.choose(running: .none)
        case .swimming:
            model.choose(swimming: .none)
        case .cycling:
            model.choose(cycling: .under20)
        }
    }

    private func summary(_ sport: Sport) -> String {
        switch sport {
        case .running:
            switch model.setup.baseline.running {
            case .none: "Not currently running"
            case .runWalk: "15–20 min run/walk"
            case .continuous10Minutes: "10 min continuous"
            case .continuous20To30Minutes: "20–30 min continuous"
            case .regular5K: "Regularly running 5 km"
            }

        case .swimming:
            model.setup.baseline.swimming.displayName

        case .cycling:
            model.setup.baseline.cycling.displayName
        }
    }
}
