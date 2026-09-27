import SwiftUI

/// First screen.
struct WelcomeStepView: View {
    var isUpgrade: Bool
    let start: () -> Void

    var body: some View {
        OnboardingStep(primaryTitle: "Build My Plan", primary: start) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ATHEVIA")
                        .font(.largeTitle.weight(.bold))
                    Text("Training that adapts to you.")
                        .font(.title3)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
                .padding(.top, 40)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    sportLabel("RUN", systemImage: "figure.run", tint: Discipline.running.tint)
                    sportLabel("SWIM", systemImage: "figure.pool.swim", tint: Discipline.swimming.tint)
                    sportLabel("BIKE", systemImage: "figure.outdoor.cycle", tint: Discipline.cycling.tint)
                }
                .font(.caption.weight(.semibold))

                if isUpgrade {
                    Text("Your training history stays exactly as it is.")
                        .font(.subheadline)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func sportLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
        }
    }
}

struct GoalStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(primary: model.advance) {
            OnboardingHeader(
                title: "What are you training for?"
            )

            VStack(spacing: 10) {
                ForEach(TrainingGoal.allCases, id: \.self) { goal in
                    OptionCard(
                        title: goal.displayName,
                        isSelected: model.setup.goal == goal
                    ) {
                        model.choose(goal: goal)
                    }
                }
            }
        }
    }
}

struct RunningStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(primary: model.advance) {
            OnboardingHeader(
                title: RunningBaseline.none.question,
                subtitle: "Answer for where you are now, not where you have been."
            )

            VStack(spacing: 10) {
                ForEach(RunningBaseline.allCases, id: \.self) { baseline in
                    OptionCard(
                        title: baseline.displayName,
                        isSelected: model.setup.baseline.running == baseline
                    ) {
                        model.choose(running: baseline)
                    }
                }
            }
        }
    }
}

struct SwimmingStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(primary: model.advance) {
            OnboardingHeader(
                title: SwimmingBaseline.none.question,
                subtitle: "Without stopping at the wall, and without a rest."
            )

            VStack(spacing: 10) {
                ForEach(SwimmingBaseline.allCases, id: \.self) { baseline in
                    OptionCard(
                        title: baseline.displayName,
                        isSelected: model.setup.baseline.swimming == baseline
                    ) {
                        model.choose(swimming: baseline)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Main stroke")

                HStack(spacing: 10) {
                    ForEach(SwimStroke.allCases, id: \.self) { stroke in
                        OptionCard(
                            title: stroke.displayName,
                            isSelected: model.setup.baseline.stroke == stroke
                        ) {
                            model.choose(stroke: stroke)
                        }
                    }
                }
            }
        }
    }
}

struct CyclingStepView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStep(primary: model.advance) {
            OnboardingHeader(
                title: CyclingBaseline.under20.question,
                subtitle: "At an easy effort you could hold a conversation through."
            )

            VStack(spacing: 10) {
                ForEach(CyclingBaseline.allCases, id: \.self) { baseline in
                    OptionCard(
                        title: baseline.displayName,
                        isSelected: model.setup.baseline.cycling == baseline
                    ) {
                        model.choose(cycling: baseline)
                    }
                }
            }
        }
    }
}

struct PoolStepView: View {
    @Bindable var model: OnboardingModel
    @State private var customLength = ""
    @FocusState private var isEditingCustom: Bool

    private var isStandard: Bool {
        model.poolLengthMeters == 25 || model.poolLengthMeters == 50
    }

    var body: some View {
        OnboardingStep(isPrimaryEnabled: model.canAdvance, primary: model.advance) {
            OnboardingHeader(
                title: "What pool do you usually train in?",
                subtitle: "Sets are built in whole lengths, so this decides how your swims are written."
            )

            VStack(spacing: 10) {
                OptionCard(
                    title: "25 m",
                    detail: "The most common pool",
                    isSelected: model.poolLengthMeters == 25
                ) {
                    isEditingCustom = false
                    model.setPoolLength(25)
                }
                OptionCard(
                    title: "50 m",
                    detail: "Olympic length",
                    isSelected: model.poolLengthMeters == 50
                ) {
                    isEditingCustom = false
                    model.setPoolLength(50)
                }
                OptionCard(title: "Other", isSelected: !isStandard) {
                    isEditingCustom = true
                }
            }

            if !isStandard || isEditingCustom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Length", text: $customLength)
                            .keyboardType(.decimalPad)
                            .focused($isEditingCustom)
                            .onChange(of: customLength) { _, value in
                                if let meters = Double(value), PoolLength.isValid(meters) {
                                    model.setPoolLength(meters)
                                }
                            }
                        Text("m")
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    }
                    .padding(14)
                    .background(AtheviaAdaptiveStyle(.background.secondary, gaming: .surface), in: .rect(cornerRadius: 14))

                    if !customLength.isEmpty,
                       Double(customLength).map({ !PoolLength.isValid($0) }) ?? true {
                        Text("Enter a length between \(Int(PoolLength.permittedRange.lowerBound)) and \(Int(PoolLength.permittedRange.upperBound)) metres.")
                            .font(.footnote)
                            .foregroundStyle(AtheviaAdaptiveStyle(.orange, gaming: .warning))
                    }
                }
            }
        }
        .onAppear {
            if !isStandard { customLength = String(Int(model.poolLengthMeters)) }
        }
    }
}

