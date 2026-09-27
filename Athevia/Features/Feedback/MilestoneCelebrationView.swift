import Foundation
import SwiftUI

struct MilestoneCelebrationView: View {
    let milestones: [JourneyMilestone]
    let unlockedGear: [AvatarGearItem]
    let workout: PlannedWorkout
    let avatar: AthleteAvatar
    let onDone: () -> Void

    @Environment(\.atheviaTheme) private var theme
    @State private var showsShare = false

    private var primary: JourneyMilestone? { milestones.first }

    private var sport: Sport {
        workout.discipline.sport
    }

    private var title: String {
        switch sport {
        case .running: "Great run!"
        case .cycling: "Great ride!"
        case .swimming: "Great swim!"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    metrics

                    if !unlockedGear.isEmpty {
                        unlockedGearCard
                    }

                    if !milestones.isEmpty {
                        milestoneCard
                    }

                    if let primary {
                        Button {
                            showsShare = true
                        } label: {
                            Label("Share achievement", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .sheet(isPresented: $showsShare) {
                            WorkoutShareView(
                                workout: workout,
                                titleOverride: primary.kind.displayName
                            )
                        }
                    }

                    Button(unlockedGear.isEmpty ? "Done" : "View in wardrobe") {
                        onDone()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())

                    if !unlockedGear.isEmpty {
                        Button("Done", action: onDone)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.015, green: 0.025, blue: 0.045),
                        Color(red: 0.025, green: 0.045, blue: 0.075)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            sport.discipline.themedTint(theme).opacity(0.34),
                            Color(red: 0.055, green: 0.08, blue: 0.13),
                            Color(red: 0.015, green: 0.025, blue: 0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(sport.discipline.themedTint(theme).opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 24)
                .offset(x: 90, y: 80)

            AthleteAvatarView(
                avatar: avatar,
                sport: sport,
                pose: .celebration,
                size: 350
            )
            .frame(maxWidth: .infinity)
            .frame(height: 350)
            .padding(.top, 54)

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: 28))

            VStack(spacing: 6) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text("Workout complete")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.66))
            }
            .padding(.top, 18)

            if !unlockedGear.isEmpty {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("New gear unlocked")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(height: 430)
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric(
                value: distanceText,
                label: "Distance"
            )
            Divider()
                .frame(height: 36)
                .overlay(.white.opacity(0.12))
            metric(
                value: durationText,
                label: "Duration"
            )
            Divider()
                .frame(height: 36)
                .overlay(.white.opacity(0.12))
            metric(
                value: paceText,
                label: paceLabel
            )
        }
        .padding(.vertical, 14)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity)
    }

    private var unlockedGearCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEW GEAR UNLOCKED")
                .font(.caption2.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.54))

            ForEach(unlockedGear.prefix(3)) { item in
                HStack(spacing: 14) {
                    gearArtwork(item)
                        .frame(width: 74, height: 74)
                        .background(.white.opacity(0.06), in: .rect(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Added to your wardrobe")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding(12)
                .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var milestoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MILESTONES")
                .font(.caption2.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.54))

            ForEach(milestones.prefix(3)) { milestone in
                HStack(spacing: 12) {
                    Image(systemName: "medal.fill")
                        .foregroundStyle(sport.discipline.themedTint(theme))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.06), in: .circle)

                    Text(milestone.kind.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private func gearArtwork(_ item: AvatarGearItem) -> some View {
        switch item.id {
        case .runTopIvory:
            Image("AvatarGearRunTopIvory")
                .resizable()
                .scaledToFit()
                .padding(8)
        case .runShoeCobalt:
            Image("AvatarGearRunShoeCobalt")
                .resizable()
                .scaledToFit()
                .padding(6)
        default:
            Image(systemName: item.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var distanceText: String {
        guard let meters = workout.importedSummary?.distanceMeters, meters > 0 else {
            return "—"
        }

        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        return "(Int(meters.rounded())) m"
    }

    private var durationText: String {
        guard let seconds = workout.importedSummary?.duration, seconds > 0 else {
            return "—"
        }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private var paceLabel: String {
        switch sport {
        case .running: "Avg pace"
        case .cycling: "Avg speed"
        case .swimming: "Avg pace"
        }
    }

    private var paceText: String {
        guard let summary = workout.importedSummary,
              let meters = summary.distanceMeters,
              meters > 0,
              summary.duration > 0 else {
            return "—"
        }

        switch sport {
        case .running:
            let secondsPerKm = summary.duration / (meters / 1_000)
            let minutes = Int(secondsPerKm) / 60
            let seconds = Int(secondsPerKm) % 60
            return String(format: "%d:%02d", minutes, seconds)
        case .cycling:
            let hours = summary.duration / 3_600
            guard hours > 0 else { return "—" }
            return String(format: "%.1f", (meters / 1_000) / hours)
        case .swimming:
            let secondsPer100 = summary.duration / (meters / 100)
            let minutes = Int(secondsPer100) / 60
            let seconds = Int(secondsPer100) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
