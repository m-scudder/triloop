import SwiftUI
import Combine

/// First screen. A minimal, auto-playing Run / Swim / Cycle carousel.
struct WelcomeStepView: View {
    var isUpgrade: Bool
    let start: () -> Void

    @State private var selectedSport = 0

    private let sports = [
        "onboarding_run",
        "onboarding_swim",
        "onboarding_cycle"
    ]

    private let carouselTimer = Timer.publish(
        every: 3.5,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        OnboardingStep(primaryTitle: "Build My Plan", primary: start) {
            TabView(selection: $selectedSport) {
                ForEach(Array(sports.enumerated()), id: \.offset) { index, assetName in
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 520)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 28,
                                style: .continuous
                            )
                        )
                        .tag(index)
                        .accessibilityHidden(true)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 520)
            .onReceive(carouselTimer) { _ in
                withAnimation(.easeInOut(duration: 0.5)) {
                    selectedSport = (selectedSport + 1) % sports.count
                }
            }
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
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.background.secondary, in: .rect(cornerRadius: 14))

                    if !customLength.isEmpty,
                       Double(customLength).map({ !PoolLength.isValid($0) }) ?? true {
                        Text("Enter a length between \(Int(PoolLength.permittedRange.lowerBound)) and \(Int(PoolLength.permittedRange.upperBound)) metres.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .onAppear {
            if !isStandard { customLength = String(Int(model.poolLengthMeters)) }
        }
    }
}
