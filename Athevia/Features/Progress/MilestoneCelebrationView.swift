import SwiftUI

struct MilestoneCelebrationView: View {
    let workout: PlannedWorkout
    let milestones: [JourneyMilestone]
    let onDone: () -> Void

    @State private var sharingMilestone: JourneyMilestone?

    private var primary: JourneyMilestone? {
        milestones.last
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "flag.checkered.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(workout.discipline.tint)

                if let primary {
                    VStack(spacing: 6) {
                        Text(primary.kind.displayName)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(primary.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if milestones.count > 1 {
                        Text("+\(milestones.count - 1) more milestone\(milestones.count == 2 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        sharingMilestone = primary
                    } label: {
                        Label("Share milestone", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }

                Button("Continue", action: onDone)
                    .buttonStyle(PrimaryActionButtonStyle())

                Spacer()
            }
            .padding(24)
            .navigationTitle("Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $sharingMilestone) { milestone in
                WorkoutShareView(
                    workout: workout,
                    titleOverride: milestone.kind.displayName
                )
            }
        }
    }
}
