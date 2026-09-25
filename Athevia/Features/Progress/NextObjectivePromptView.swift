import SwiftUI

struct NextObjectivePromptView: View {
    let event: AthleteEventGoal
    @Bindable var profile: AthleteProfile

    private let options = [
        ("arrow.clockwise", "Repeat this distance"),
        ("calendar.badge.plus", "Choose another event"),
        ("arrow.up.right", "Move to the next distance"),
        ("speedometer", "Improve performance"),
        ("figure.mixed.cardio", "Return to general fitness")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "What’s next?")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recovery is complete. Choose the next objective when you’re ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(options, id: \.1) { option in
                        Label(option.1, systemImage: option.0)
                            .font(.subheadline)
                    }

                    NavigationLink {
                        TrainingProfileView(profile: profile)
                    } label: {
                        Text("Choose next objective")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
            }
        }
    }
}
