import SwiftUI

struct MilestoneCelebrationView: View {
    let milestones: [JourneyMilestone]
    let workout: PlannedWorkout
    let onDone: () -> Void

    @State private var showsShare = false

    private var primary: JourneyMilestone? { milestones.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.tint)

                VStack(spacing: 6) {
                    Text("Milestone reached")
                        .font(.title2.weight(.semibold))

                    ForEach(milestones.prefix(3)) { milestone in
                        Text(milestone.kind.displayName)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                }

                if let primary {
                    Button {
                        showsShare = true
                    } label: {
                        Label("Share milestone", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Uses your completed workout evidence")
                    .sheet(isPresented: $showsShare) {
                        WorkoutShareView(
                            workout: workout,
                            titleOverride: primary.kind.displayName
                        )
                    }
                }

                Button("Continue", action: onDone)
                    .buttonStyle(PrimaryActionButtonStyle())
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
