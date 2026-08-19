import SwiftData
import SwiftUI

/// Drives the onboarding flow, one decision per screen.
///
/// Resumes wherever the athlete stopped: the stage lives in the stored setup,
/// not in view state, so quitting mid-flow loses nothing.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: OnboardingModel?

    var body: some View {
        Group {
            if let model {
                NavigationStack {
                    step(for: model)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { toolbar(model) }
                }
                .alert("Setup", isPresented: alert(model)) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.failure ?? "")
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            // Built here rather than in an initialiser: the model needs the
            // environment's context, which is not available until the view runs.
            if model == nil { model = OnboardingModel(context: modelContext) }
        }
    }

    @ViewBuilder
    private func step(for model: OnboardingModel) -> some View {
        switch model.stage {
        case .welcome:
            WelcomeStepView(isUpgrade: model.isUpgrade, start: model.advance)
        case .about:
            AboutYouStepView(model: model)
        case .goal:
            GoalStepView(model: model)
        case .running:
            RunningStepView(model: model)
        case .swimming:
            SwimmingStepView(model: model)
        case .cycling:
            CyclingStepView(model: model)
        case .days:
            TrainingDaysStepView(model: model)
        case .commitment:
            CommitmentStepView(model: model)
        case .pool:
            PoolStepView(model: model)
        case .health:
            HealthStepView(model: model)
        case .watch:
            WatchStepView(model: model)
        case .preview, .complete:
            PlanPreviewStepView(model: model)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ model: OnboardingModel) -> some ToolbarContent {
        if model.stage != .welcome {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            ToolbarItem(placement: .principal) {
                ProgressView(value: progress(model.stage))
                    .frame(width: 120)
                    .accessibilityLabel("Setup progress")
            }
        }
    }

    /// Welcome and complete are not steps the athlete answers, so progress is
    /// measured across the questions between them.
    private func progress(_ stage: AthleteSetup.Stage) -> Double {
        let total = Double(AthleteSetup.Stage.allCases.count - 1)
        return min(Double(stage.order) / total, 1)
    }

    private func alert(_ model: OnboardingModel) -> Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { _ in })
    }
}

#if DEBUG
#Preview {
    OnboardingView()
        .modelContainer(PreviewData.container)
}
#endif
