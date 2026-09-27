import SwiftUI

struct StartingPointStepView: View {
    @Environment(\.atheviaTheme) private var theme

    @Bindable var model: OnboardingModel
    @State private var poolText = ""
    @State private var customPoolSelected = false
    @FocusState private var isEditingPool: Bool

    private let compactColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(title: "Where are you starting?")

            VStack(spacing: 12) {
                ForEach([Sport.running, .cycling, .swimming], id: \.self) { sport in
                    sportCard(sport)
                }
            }

            if model.selectedSports.isEmpty {
                Label("Select at least one sport.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            } else if model.isSportSelected(.swimming),
                      !PoolLength.isValid(model.poolLengthMeters) {
                Label("Choose a valid pool length.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(AtheviaAdaptiveStyle(.orange, gaming: .warning))
            }
        }
        .toolbar {
            if isEditingPool {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        isEditingPool = false
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
    }

    @ViewBuilder
    private func sportCard(_ sport: Sport) -> some View {
        let selected = model.isSportSelected(sport)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                model.toggleSport(sport)
                if !selected && sport == .swimming {
                    preparePoolState()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(
                            selected
                                ? AnyShapeStyle(sport.discipline.themedTint(theme))
                                : AnyShapeStyle(.secondary)
                        )

                    DisciplineBadge(discipline: sport.discipline, size: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(sport.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if selected {
                            Text(summary(sport))
                                .font(.subheadline)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("startingPoint.\(sport.rawValue)")
            .accessibilityLabel("\(sport.displayName), \(selected ? "selected" : "not selected")")
            .accessibilityAddTraits(selected ? [.isSelected] : [])

            if selected {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 12) {
                    SectionEyebrow(text: abilityTitle(for: sport))
                    baselineChoices(sport)

                    if sport == .swimming {
                        swimmingDetails
                    }
                }
                .padding(14)
            }
        }
        .background(AtheviaAdaptiveStyle(.background.secondary, gaming: .surface), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    selected ? sport.discipline.themedTint(theme).opacity(0.75) : Color.secondary.opacity(0.18),
                    lineWidth: selected ? 1.5 : 0.5
                )
        )
    }

    private func abilityTitle(for sport: Sport) -> String {
        switch sport {
        case .running: "Running now"
        case .swimming: "Longest continuous swim"
        case .cycling: "Comfortable ride"
        }
    }

    @ViewBuilder
    private func baselineChoices(_ sport: Sport) -> some View {
        LazyVGrid(columns: compactColumns, spacing: 8) {
            switch sport {
            case .running:
                ForEach(RunningBaseline.allCases, id: \.self) { baseline in
                    AtheviaChoiceChip(
                        title: shortLabel(baseline),
                        isSelected: model.setup.baseline.running == baseline,
                        tint: sport.discipline.themedTint(theme)
                    ) {
                        model.choose(running: baseline)
                    }
                }

            case .swimming:
                ForEach(SwimmingBaseline.allCases, id: \.self) { baseline in
                    AtheviaChoiceChip(
                        title: baseline.displayName,
                        isSelected: model.setup.baseline.swimming == baseline,
                        tint: sport.discipline.themedTint(theme)
                    ) {
                        model.choose(swimming: baseline)
                    }
                }

            case .cycling:
                ForEach(CyclingBaseline.allCases, id: \.self) { baseline in
                    AtheviaChoiceChip(
                        title: shortLabel(baseline),
                        isSelected: model.setup.baseline.cycling == baseline,
                        tint: sport.discipline.themedTint(theme)
                    ) {
                        model.choose(cycling: baseline)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var swimmingDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Stroke")

            HStack(spacing: 8) {
                ForEach(SwimStroke.allCases, id: \.self) { stroke in
                    AtheviaChoiceChip(
                        title: stroke.displayName,
                        isSelected: model.setup.baseline.stroke == stroke,
                        tint: Discipline.swimming.tint
                    ) {
                        model.choose(stroke: stroke)
                    }
                }
            }

            SectionEyebrow(text: "Pool length")

            HStack(spacing: 8) {
                poolChoice("25 m", meters: 25)
                poolChoice("50 m", meters: 50)

                AtheviaChoiceChip(
                    title: "Other",
                    isSelected: customPoolSelected,
                    tint: Discipline.swimming.tint
                ) {
                    customPoolSelected = true
                    poolText = ""
                    model.setPoolLength(0)
                    isEditingPool = true
                }
            }

            if customPoolSelected {
                TextField("Pool length in metres", text: $poolText)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditingPool)
                    .onSubmit { isEditingPool = false }
                    .onChange(of: poolText) { _, value in
                        let metres = (try? Double(value, format: .number)) ?? 0
                        model.setPoolLength(PoolLength.isValid(metres) ? metres : 0)
                    }
            }
        }
    }

    private func poolChoice(_ title: String, meters: Double) -> some View {
        AtheviaChoiceChip(
            title: title,
            isSelected: !customPoolSelected && model.poolLengthMeters == meters,
            tint: Discipline.swimming.tint
        ) {
            customPoolSelected = false
            poolText = ""
            isEditingPool = false
            model.setPoolLength(meters)
        }
    }

    private func preparePoolState() {
        customPoolSelected = PoolLength.isValid(model.poolLengthMeters)
            && model.poolLengthMeters != 25
            && model.poolLengthMeters != 50
        poolText = customPoolSelected
            ? model.poolLengthMeters.formatted(.number)
            : ""
    }

    private func shortLabel(_ baseline: RunningBaseline) -> String {
        switch baseline {
        case .none: "Not running yet"
        case .runWalk: "Run / walk"
        case .continuous10Minutes: "10 min"
        case .continuous20To30Minutes: "20–30 min"
        case .regular5K: "5 km+"
        }
    }

    private func shortLabel(_ baseline: CyclingBaseline) -> String {
        switch baseline {
        case .under20: "< 20 min"
        case .twentyToThirty: "20–30 min"
        case .thirtyToFortyFive: "30–45 min"
        case .fortyFiveToSixty: "45–60 min"
        case .sixtyPlus: "60+ min"
        }
    }

    private func summary(_ sport: Sport) -> String {
        switch sport {
        case .running:
            shortLabel(model.setup.baseline.running)
        case .swimming:
            model.setup.baseline.swimming.displayName
        case .cycling:
            shortLabel(model.setup.baseline.cycling)
        }
    }
}

