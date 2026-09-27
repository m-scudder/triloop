import SwiftUI
import UIKit

/// Production avatar presentation.
///
/// Validated appearance/loadout combinations resolve to high-resolution rendered
/// character assets. The vector construction remains only as a temporary fallback
/// while the production catalog is expanded.
private enum AvatarRenderAssetResolver {
    static func assetName(
        for avatar: AthleteAvatar,
        sport: Sport,
        pose: AvatarPose
    ) -> String? {
        let canonical = canonicalAssetName(
            for: avatar,
            sport: sport,
            pose: pose
        )

        if UIImage(named: canonical) != nil {
            return canonical
        }

        // Compatibility with the first proof-of-quality vertical slice.
        guard pose == .neutral,
              sport == .running,
              avatar.presentation == .feminine,
              avatar.skinTone == .warmMedium,
              avatar.hairStyle == .tied,
              avatar.hairColor == .espresso,
              avatar.bodyPreset == .balanced else {
            return nil
        }

        let loadout = avatar.loadout(for: sport)
        guard loadout.bottom == .runShortBlack,
              loadout.headwear == nil,
              loadout.accessory == nil else {
            return nil
        }

        switch (loadout.top, loadout.footwear) {
        case (.runTopLavender, .runShoeWhite):
            return "AvatarFemaleBalancedStarterRun"
        case (.runTopIvory, .runShoeWhite):
            return "AvatarFemaleBalancedRunTopIvory"
        case (.runTopLavender, .runShoeCobalt):
            return "AvatarFemaleBalancedRunShoeCobalt"
        default:
            return nil
        }
    }

    static func canonicalAssetName(
        for avatar: AthleteAvatar,
        sport: Sport,
        pose: AvatarPose
    ) -> String {
        let loadout = avatar.loadout(for: sport)
        return [
            "AvatarRender",
            avatar.presentation.rawValue,
            avatar.bodyPreset.rawValue,
            avatar.skinTone.rawValue,
            avatar.hairStyle.rawValue,
            avatar.hairColor.rawValue,
            sport.rawValue,
            loadout.top.rawValue,
            loadout.bottom.rawValue,
            loadout.footwear.rawValue,
            loadout.headwear?.rawValue ?? "none",
            loadout.accessory?.rawValue ?? "none",
            pose.rawValue
        ]
        .joined(separator: "__")
    }
}


struct AthleteAvatarView: View {
    let avatar: AthleteAvatar
    var sport: Sport = .running
    var pose: AvatarPose = .neutral
    var size: CGFloat = 280

    private var skin: Color {
        let rgb = avatar.skinTone.rgb
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private var hair: Color {
        let rgb = avatar.hairColor.rgb
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private var loadout: AvatarLoadout {
        avatar.loadout(for: sport)
    }

    private var sportAccent: Color {
        switch sport {
        case .running: Color(red: 0.32, green: 0.42, blue: 0.96)
        case .cycling: Color(red: 0.12, green: 0.70, blue: 0.65)
        case .swimming: Color(red: 0.12, green: 0.60, blue: 0.92)
        }
    }

    private var topColor: Color {
        switch loadout.top {
        case .runTopLavender:
            Color(red: 0.47, green: 0.42, blue: 0.88)
        case .runTopIvory:
            Color(red: 0.92, green: 0.91, blue: 0.88)
        case .runTopCobalt, .cycleJerseyCobalt, .swimSuitCobalt:
            Color(red: 0.18, green: 0.32, blue: 0.88)
        case .cycleJerseyGraphite, .runTopGraphite, .swimSuitGraphite:
            Color(red: 0.12, green: 0.13, blue: 0.16)
        default:
            sportAccent
        }
    }

    private var bottomColor: Color {
        switch loadout.bottom {
        case .runShortSlate:
            Color(red: 0.22, green: 0.24, blue: 0.29)
        default:
            Color(red: 0.07, green: 0.08, blue: 0.10)
        }
    }

    private var footwearColor: Color {
        switch loadout.footwear {
        case .runShoeCobalt:
            Color(red: 0.18, green: 0.32, blue: 0.88)
        case .cycleShoeBlack:
            Color(red: 0.06, green: 0.07, blue: 0.09)
        case .barefoot:
            skin
        default:
            Color(red: 0.94, green: 0.94, blue: 0.92)
        }
    }

    private var productionAssetName: String? {
        AvatarRenderAssetResolver.assetName(
            for: avatar,
            sport: sport,
            pose: pose
        )
    }

    var body: some View {
        Group {
            if let productionAssetName {
                Image(productionAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.72, height: size)
            } else {
                ZStack {
                    Ellipse()
                        .fill(.black.opacity(0.10))
                        .frame(width: size * 0.42, height: size * 0.055)
                        .offset(y: size * 0.42)
                        .blur(radius: 3)

                    legs
                    torso
                    arms
                    head
                    hairShape
                    headwearLayer
                    accessoryLayer
                }
                .frame(width: size * 0.68, height: size)
                .drawingGroup()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Athlete avatar")
    }

    private var legs: some View {
        HStack(spacing: size * 0.045) {
            Capsule()
                .fill(skin)
                .frame(width: size * 0.075, height: size * 0.31)
            Capsule()
                .fill(skin)
                .frame(width: size * 0.075, height: size * 0.31)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: size * 0.018) {
                shoe
                shoe
            }
            .offset(y: size * 0.035)
        }
        .offset(y: size * 0.25)
    }

    private var shoe: some View {
        Capsule()
            .fill(footwearColor)
            .overlay {
                Capsule()
                    .stroke(.black.opacity(0.12), lineWidth: 1)
            }
            .frame(width: size * 0.12, height: size * 0.045)
    }

    private var torso: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [topColor.opacity(0.98), topColor.opacity(0.76)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: size * 0.32 * avatar.bodyPreset.shoulderScale,
                    height: size * 0.22
                )

            RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
                .fill(bottomColor)
                .frame(width: size * 0.30, height: size * 0.12)
                .offset(y: -size * 0.018)
        }
        .offset(y: size * 0.045)
    }

    private var arms: some View {
        HStack(spacing: size * 0.29 * avatar.bodyPreset.shoulderScale) {
            Capsule()
                .fill(skin)
                .frame(width: size * 0.055, height: size * 0.26)
                .rotationEffect(.degrees(7))
            Capsule()
                .fill(skin)
                .frame(width: size * 0.055, height: size * 0.26)
                .rotationEffect(.degrees(-7))
        }
        .offset(y: size * 0.065)
    }

    private var head: some View {
        VStack(spacing: -2) {
            Ellipse()
                .fill(skin)
                .frame(width: size * 0.17, height: size * 0.205)
                .overlay(alignment: .center) {
                    HStack(spacing: size * 0.045) {
                        Circle().fill(.black.opacity(0.72)).frame(width: 3.5, height: 3.5)
                        Circle().fill(.black.opacity(0.72)).frame(width: 3.5, height: 3.5)
                    }
                    .offset(y: -size * 0.015)
                }

            Capsule()
                .fill(skin)
                .frame(width: size * 0.065, height: size * 0.05)
        }
        .offset(y: -size * 0.225)
    }

    @ViewBuilder
    private var hairShape: some View {
        switch avatar.hairStyle {
        case .cropped, .closeCut:
            Ellipse()
                .trim(from: 0, to: 0.56)
                .fill(hair)
                .frame(width: size * 0.18, height: size * 0.16)
                .rotationEffect(.degrees(180))
                .offset(y: -size * 0.285)
        case .swept, .textured:
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(hair)
                .frame(width: size * 0.19, height: size * 0.095)
                .rotationEffect(.degrees(-7))
                .offset(y: -size * 0.31)
        case .tied:
            ZStack {
                Ellipse()
                    .fill(hair)
                    .frame(width: size * 0.18, height: size * 0.10)
                Circle()
                    .fill(hair)
                    .frame(width: size * 0.065, height: size * 0.065)
                    .offset(x: size * 0.085, y: -size * 0.02)
            }
            .offset(y: -size * 0.31)
        case .long:
            Capsule()
                .fill(hair)
                .frame(width: size * 0.20, height: size * 0.25)
                .offset(y: -size * 0.24)
                .overlay {
                    Ellipse()
                        .fill(skin)
                        .frame(width: size * 0.155, height: size * 0.19)
                        .offset(y: -size * 0.255)
                }
        }
    }
    @ViewBuilder
    private var headwearLayer: some View {
        switch loadout.headwear {
        case .runCapBlack:
            ZStack {
                Capsule()
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.09))
                    .frame(width: size * 0.19, height: size * 0.07)
                Capsule()
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.09))
                    .frame(width: size * 0.10, height: size * 0.025)
                    .offset(x: size * 0.075, y: size * 0.025)
            }
            .offset(y: -size * 0.32)

        case .cycleHelmetBlack, .cycleHelmetWhite:
            let helmetColor = loadout.headwear == .cycleHelmetWhite
                ? Color(red: 0.92, green: 0.93, blue: 0.94)
                : Color(red: 0.05, green: 0.06, blue: 0.08)

            ZStack {
                Ellipse()
                    .fill(helmetColor)
                    .frame(width: size * 0.20, height: size * 0.10)
                HStack(spacing: size * 0.016) {
                    Capsule().fill(.black.opacity(0.28))
                    Capsule().fill(.black.opacity(0.28))
                    Capsule().fill(.black.opacity(0.28))
                }
                .frame(width: size * 0.13, height: size * 0.018)
            }
            .offset(y: -size * 0.325)

        case .swimCapBlack, .swimCapWhite:
            Ellipse()
                .fill(
                    loadout.headwear == .swimCapWhite
                        ? Color(red: 0.93, green: 0.94, blue: 0.95)
                        : Color(red: 0.05, green: 0.06, blue: 0.08)
                )
                .frame(width: size * 0.185, height: size * 0.105)
                .offset(y: -size * 0.315)

        case .none:
            EmptyView()

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var accessoryLayer: some View {
        if loadout.accessory == .swimGogglesSmoke {
            HStack(spacing: size * 0.01) {
                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: size * 0.055, height: size * 0.025)
                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: size * 0.055, height: size * 0.025)
            }
            .overlay {
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: size * 0.02, height: size * 0.008)
            }
            .offset(y: -size * 0.255)
        }
    }
}

struct AthleteAvatarStudioView: View {
    @Environment(\.atheviaTheme) private var theme
    @Binding var avatar: AthleteAvatar
    var selectedSports: [Sport]
    var showsCompletionButton = false
    var onComplete: (() -> Void)?

    @State private var selectedSport: Sport = .running

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                sportSelector
                appearance
                starterKit

                if showsCompletionButton {
                    Button("Continue") {
                        onComplete?()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .atheviaScreen()
        .navigationTitle("My Athlete")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let first = selectedSports.first {
                selectedSport = first
            }
        }
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.color(.hero, classic: Color(red: 0.08, green: 0.10, blue: 0.16)),
                            theme.color(.canvas, classic: Color(red: 0.02, green: 0.03, blue: 0.06))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(theme.color(.accent, classic: .white).opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 2)
                .offset(x: 90, y: -80)

            VStack(spacing: 10) {
                AthleteAvatarView(avatar: avatar, sport: selectedSport, size: 310)
                    .frame(height: 310)

                VStack(spacing: 4) {
                    Text("YOUR ATHLETE")
                        .font(.caption.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.58))
                    Text(selectedSport.displayName + " look")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 18)
            }
        }
        .frame(minHeight: 390)
        .clipShape(.rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 24, y: 12)
    }

    @ViewBuilder
    private var sportSelector: some View {
        if selectedSports.count > 1 {
            Picker("Outfit", selection: $selectedSport) {
                ForEach(selectedSports, id: \.self) { sport in
                    Text(sport.displayName).tag(sport)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                "Appearance",
                detail: "Build a recognizable athlete identity. You can change this later."
            )

            controlRow("Style") {
                Picker("Style", selection: $avatar.presentation) {
                    ForEach(AvatarPresentation.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Skin tone")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    ForEach(AvatarSkinTone.allCases) { tone in
                        Button {
                            avatar.skinTone = tone
                        } label: {
                            Circle()
                                .fill(skinColor(tone))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            avatar.skinTone == tone
                                                ? theme.color(.accent, classic: .blue)
                                                : .white.opacity(0.10),
                                            lineWidth: avatar.skinTone == tone ? 3 : 1
                                        )
                                        .padding(-3)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tone.rawValue)
                        .accessibilityAddTraits(avatar.skinTone == tone ? .isSelected : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Hair")
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(AvatarHairStyle.allCases) { style in
                        premiumChoice(
                            title: style.displayName,
                            selected: avatar.hairStyle == style
                        ) {
                            avatar.hairStyle = style
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Build")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    ForEach(AvatarBodyPreset.allCases) { preset in
                        premiumChoice(
                            title: preset.displayName,
                            selected: avatar.bodyPreset == preset
                        ) {
                            avatar.bodyPreset = preset
                        }
                    }
                }
            }
        }
    }

    private var starterKit: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                "Starter kit",
                detail: "Training unlocks additional gear. Cosmetic choices never affect your plan."
            )

            HStack(spacing: 12) {
                gearCard(icon: "tshirt.fill", title: "Performance top")
                gearCard(icon: "shoe.fill", title: "Training shoes")
                gearCard(icon: selectedSport == .cycling ? "bicycle.helmet" : "sparkles", title: "Sport kit")
            }
        }
    }

    private func controlRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
    }

    private func premiumChoice(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? theme.color(.onAccent, classic: .white) : .primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selected
                        ? theme.color(.accent, classic: .blue)
                        : theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
                    in: .rect(cornerRadius: 13)
                )
        }
        .buttonStyle(.plain)
    }

    private func gearCard(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .frame(height: 28)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(10)
        .background(
            theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
            in: .rect(cornerRadius: 18)
        )
    }

    private func skinColor(_ tone: AvatarSkinTone) -> Color {
        let rgb = tone.rgb
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

struct AthleteAvatarOnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        AthleteAvatarStudioView(
            avatar: Binding(
                get: { model.avatar },
                set: { model.choose(avatar: $0) }
            ),
            selectedSports: model.selectedSports.isEmpty ? [.running] : model.selectedSports,
            showsCompletionButton: true,
            onComplete: model.advance
        )
        .navigationTitle("Create your athlete")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Athlete Studio") {
    NavigationStack {
        AthleteAvatarStudioView(
            avatar: .constant(.starter),
            selectedSports: [.running, .cycling, .swimming]
        )
    }
}
#endif
