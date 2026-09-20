import SwiftUI

struct StartingPointStepView: View {
    @Bindable var model: OnboardingModel
    @State private var selectedSport: Sport?
    @State private var poolText = ""

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(title: "Where are you starting?", subtitle: "What can you comfortably do today?")
            ForEach(Sport.allCases, id: \.self) { sport in
                Button {
                    poolText = model.poolLengthMeters.formatted(.number)
                    selectedSport = sport
                } label: {
                    HStack(spacing: 12) {
                        DisciplineBadge(discipline: sport.discipline, size: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sport.displayName).font(.headline)
                            Text(summary(sport)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("startingPoint.\(sport.rawValue)")
                .accessibilityLabel("\(sport.displayName), \(summary(sport)), edit starting point")
            }
            if !PoolLength.isValid(model.poolLengthMeters) {
                Text("Choose a valid pool length in Swimming.")
                    .foregroundStyle(.orange)
            }
        }
        .sheet(isPresented: Binding(get: { selectedSport != nil }, set: { if !$0 { selectedSport = nil } })) {
            if let sport = selectedSport {
                ExplanationSheet(title: sport.displayName) {
                    Section("What can you comfortably do today?") {
                        baselineChoices(sport)
                    }
                    if sport == .swimming {
                        Section("Stroke") {
                            Picker("Primary stroke", selection: Binding(get: { model.setup.baseline.stroke }, set: { model.choose(stroke: $0) })) {
                                ForEach(SwimStroke.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                        }
                        Section("Pool") {
                            HStack {
                                Button("25 m") { poolText = "25" }
                                Button("50 m") { poolText = "50" }
                            }
                            .buttonStyle(.bordered)
                            TextField("Length in metres", text: $poolText)
                                .keyboardType(.decimalPad)
                                .accessibilityLabel("Pool length in metres")
                                .onChange(of: poolText) { _, value in
                                    model.setPoolLength((try? Double(value, format: .number)) ?? 0)
                                }
                            if !PoolLength.isValid(model.poolLengthMeters) {
                                Text("Enter a pool length between \(Int(PoolLength.permittedRange.lowerBound)) and \(Int(PoolLength.permittedRange.upperBound)) metres.")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func baselineChoices(_ sport: Sport) -> some View {
        switch sport {
        case .running:
            ForEach(RunningBaseline.allCases, id: \.self) { baseline in
                baselineChoice(baseline.displayName, selected: model.setup.baseline.running == baseline) {
                    model.choose(running: baseline)
                }
            }
            Button("Not sure - start with run/walk") { model.choose(running: .none) }
        case .swimming:
            ForEach(SwimmingBaseline.allCases, id: \.self) { baseline in
                baselineChoice(baseline.displayName, selected: model.setup.baseline.swimming == baseline) {
                    model.choose(swimming: baseline)
                }
            }
            Button("Not sure - start with supported practice") { model.choose(swimming: .none) }
            Text("Get instruction if you cannot swim safely. Only practise where you have appropriate supervision.")
                .font(.footnote)
        case .cycling:
            ForEach(CyclingBaseline.allCases, id: \.self) { baseline in
                baselineChoice(baseline.displayName, selected: model.setup.baseline.cycling == baseline) {
                    model.choose(cycling: baseline)
                }
            }
            Button("Not sure - start with a short ride") { model.choose(cycling: .under20) }
        }
    }

    private func baselineChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func summary(_ sport: Sport) -> String {
        switch sport {
        case .running:
            switch model.setup.baseline.running {
            case .none: "Not currently running"
            case .runWalk: "15-20 min run/walk"
            case .continuous10Minutes: "10 min continuous"
            case .continuous20To30Minutes: "20-30 min continuous"
            case .regular5K: "Regularly running 5 km"
            }
        case .swimming: model.setup.baseline.swimming.displayName
        case .cycling: model.setup.baseline.cycling.displayName
        }
    }
}