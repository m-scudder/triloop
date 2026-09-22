import SwiftUI

struct StartingPointStepView: View {
    @Bindable var model: OnboardingModel
    @State private var selectedSport: Sport?
    @State private var poolText = ""
    @State private var customPoolSelected = false
    @FocusState private var isEditingPool: Bool

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(
                title: "Where are you starting?",
                subtitle: "Select the sports you want to train."
            )

            VStack(spacing: 10) {
                ForEach(Sport.allCases, id: \.self) { sport in
                    sportRow(sport)
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
        .sheet(
            isPresented: Binding(
                get: { selectedSport != nil },
                set: { if !$0 { selectedSport = nil } }
            )
        ) {
            if let sport = selectedSport {
                ExplanationSheet(title: sport.displayName) {
                    Section("Starting point") {
                        baselineChoices(sport)
                        Button("Not sure") {
                            chooseConservativeDefault(for: sport)
                        }
                    }

                    if sport == .swimming {
                        Section("Stroke") {
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
                        }

                        Section("Pool length") {
                            poolChoice("25 m", meters: 25)
                            poolChoice("50 m", meters: 50)

                            Button {
                                if customPoolSelected {
                                    customPoolSelected = false
                                    isEditingPool = false
                                    poolText = ""
                                    model.setPoolLength(0)
                                } else {
                                    customPoolSelected = true
                                    poolText = ""
                                    model.setPoolLength(0)
                                    isEditingPool = true
                                }
                            } label: {
                                choiceLabel("Other", selected: customPoolSelected)
                            }

                            if customPoolSelected {
                                TextField("Length in metres", text: $poolText)
                                    .keyboardType(.decimalPad)
                                    .focused($isEditingPool)
                                    .onChange(of: poolText) { _, value in
                                        let metres = (try? Double(value, format: .number)) ?? 0
                                        model.setPoolLength(
                                            PoolLength.isValid(metres) ? metres : 0
                                        )
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
                }
            }
        }
    }

    private func sportRow(_ sport: Sport) -> some View {
        let selected = model.isSportSelected(sport)

        return HStack(spacing: 8) {
            Button {
                let wasSelected = model.isSportSelected(sport)
                model.toggleSport(sport)

                if !wasSelected {
                    openDetails(for: sport)
                } else if selectedSport == sport {
                    selectedSport = nil
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)

                    DisciplineBadge(discipline: sport.discipline, size: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(sport.displayName)
                            .font(.headline)
                        Text(selected ? summary(sport) : "Not selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("startingPoint.\(sport.rawValue)")
            .accessibilityLabel("\(sport.displayName), \(selected ? "selected" : "not selected")")
            .accessibilityAddTraits(selected ? [.isSelected] : [])

            if selected {
                Button {
                    openDetails(for: sport)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(sport.displayName) starting point")
            }
        }
    }

    private func openDetails(for sport: Sport) {
        if sport == .swimming {
            customPoolSelected = PoolLength.isValid(model.poolLengthMeters)
                && model.poolLengthMeters != 25
                && model.poolLengthMeters != 50
            poolText = customPoolSelected
                ? model.poolLengthMeters.formatted(.number)
                : ""
        } else {
            customPoolSelected = false
            poolText = ""
        }
        selectedSport = sport
    }

    @ViewBuilder
    private func baselineChoices(_ sport: Sport) -> some View {
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

    private func baselineChoice(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            choiceLabel(title, selected: selected)
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func poolChoice(_ title: String, meters: Double) -> some View {
        let selected = !customPoolSelected && model.poolLengthMeters == meters

        return Button {
            customPoolSelected = false
            isEditingPool = false
            poolText = ""

            if selected {
                model.setPoolLength(0)
            } else {
                model.setPoolLength(meters)
            }
        } label: {
            choiceLabel(title, selected: selected)
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func choiceLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }

    private func notSureTitle(for sport: Sport) -> String {
        switch sport {
        case .running:
            "Not sure - start with run/walk"
        case .swimming:
            "Not sure - start with supported practice"
        case .cycling:
            "Not sure - start with a short ride"
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

        selectedSport = nil
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
