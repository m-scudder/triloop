import SwiftUI

struct MilestoneCelebrationView: View {
    let milestones: [JourneyMilestone]
    let unlockedGear: [AvatarGearItem]
    let workout: PlannedWorkout
    let onDone: () -> Void

    @State private var showsShare = false

    private var primary: JourneyMilestone? { milestones.first }

    private var title: String {
        if !unlockedGear.isEmpty && milestones.isEmpty { return "New gear unlocked" }
        if unlockedGear.isEmpty { return "Milestone reached" }
        return "Progress unlocked"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(AtheviaAdaptiveStyle(.tint, gaming: .achievement))

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.semibold))

                    ForEach(milestones.prefix(3)) { milestone in
                        Text(milestone.kind.displayName)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                }

                if !unlockedGear.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(unlockedGear.prefix(3)) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol)
                                    .font(.title3)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface),
                                        in: .rect(cornerRadius: 12)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Added to your wardrobe")
                                        .font(.caption)
                                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AtheviaAdaptiveStyle(.green, gaming: .success))
                            }
                            .padding(12)
                            .background(
                                AtheviaAdaptiveStyle(.background.secondary, gaming: .surface),
                                in: .rect(cornerRadius: 16)
                            )
                        }
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
        .atheviaScreen()
        .presentationDetents([.medium])
    }
}
