import SwiftUI

struct AthleteAvatarIntroStepView: View {
    @Environment(\.atheviaTheme) private var theme
    @Bindable var model: OnboardingModel

    private var primarySport: Sport {
        model.selectedSports.first ?? .running
    }

    var body: some View {
        OnboardingStep(primaryTitle: "Create my athlete", primary: model.advance) {
            VStack(spacing: 22) {
                Spacer(minLength: 4)

                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.055, green: 0.075, blue: 0.12),
                                    Color(red: 0.015, green: 0.02, blue: 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Circle()
                        .fill(primarySport.discipline.themedTint(theme).opacity(0.14))
                        .frame(width: 230, height: 230)
                        .blur(radius: 8)
                        .offset(x: 80, y: -90)

                    AthleteAvatarView(
                        avatar: model.avatar,
                        sport: primarySport,
                        size: 330
                    )
                    .padding(.top, 18)
                }
                .frame(height: 410)
                .clipShape(.rect(cornerRadius: 30))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.20), radius: 24, y: 12)

                VStack(spacing: 8) {
                    Text("Build your athlete")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("A visual record of the athlete you are becoming. Train, reach milestones, and earn gear that stays part of your journey.")
                        .font(.body)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    principle("figure.run", "Real training")
                    principle("medal.fill", "Earned gear")
                    principle("person.crop.square", "Your style")
                }
            }
        }
    }

    private func principle(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
            Text(text)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .padding(10)
        .background(
            theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
            in: .rect(cornerRadius: 18)
        )
    }
}

struct AthleteAvatarAppearanceStepView: View {
    @Environment(\.atheviaTheme) private var theme
    @Bindable var model: OnboardingModel

    private var binding: Binding<AthleteAvatar> {
        Binding(
            get: { model.avatar },
            set: { model.choose(avatar: $0) }
        )
    }

    private var primarySport: Sport {
        model.selectedSports.first ?? .running
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        OnboardingStep(primary: model.advance) {
            OnboardingHeader(
                title: "Make it yours",
                subtitle: "Keep it simple now. Everything here can be changed later."
            )

            avatarStage

            VStack(alignment: .leading, spacing: 16) {
                SectionEyebrow(text: "Presentation")
                Picker("Presentation", selection: binding.presentation) {
                    ForEach(AvatarPresentation.allCases) { presentation in
                        Text(presentation.displayName).tag(presentation)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                SectionEyebrow(text: "Skin tone")
                HStack(spacing: 12) {
                    ForEach(AvatarSkinTone.allCases) { tone in
                        skinToneButton(tone)
                    }
                }

                SectionEyebrow(text: "Hair")
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(AvatarHairStyle.allCases) { style in
                        choice(
                            style.displayName,
                            selected: model.avatar.hairStyle == style
                        ) {
                            var avatar = model.avatar
                            avatar.hairStyle = style
                            model.choose(avatar: avatar)
                        }
                    }
                }

                SectionEyebrow(text: "Build")
                HStack(spacing: 10) {
                    ForEach(AvatarBodyPreset.allCases) { preset in
                        choice(
                            preset.displayName,
                            selected: model.avatar.bodyPreset == preset
                        ) {
                            var avatar = model.avatar
                            avatar.bodyPreset = preset
                            model.choose(avatar: avatar)
                        }
                    }
                }
            }
        }
    }

    private var avatarStage: some View {
        AthleteAvatarView(
            avatar: model.avatar,
            sport: primarySport,
            size: 300
        )
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .background(
            LinearGradient(
                colors: [
                    theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
                    theme.color(.surface, classic: Color(uiColor: .systemBackground))
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: .rect(cornerRadius: 26)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(theme.color(.border, classic: Color.secondary.opacity(0.14)), lineWidth: 0.5)
        }
    }

    private func skinToneButton(_ tone: AvatarSkinTone) -> some View {
        Button {
            var avatar = model.avatar
            avatar.skinTone = tone
            model.choose(avatar: avatar)
        } label: {
            let rgb = tone.rgb
            Circle()
                .fill(Color(red: rgb.0, green: rgb.1, blue: rgb.2))
                .frame(width: 36, height: 36)
                .overlay {
                    if model.avatar.skinTone == tone {
                        Circle()
                            .stroke(theme.color(.accent, classic: .blue), lineWidth: 3)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tone.rawValue)
        .accessibilityAddTraits(model.avatar.skinTone == tone ? .isSelected : [])
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? theme.color(.onAccent, classic: .white) : .primary)
                .background(
                    selected
                        ? theme.color(.accent, classic: .blue)
                        : theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
                    in: .rect(cornerRadius: 13)
                )
        }
        .buttonStyle(.plain)
    }
}

struct AthleteAvatarOutfitStepView: View {
    @Environment(\.atheviaTheme) private var theme
    @Bindable var model: OnboardingModel
    @State private var selectedSport: Sport = .running

    private var availableSports: [Sport] {
        model.selectedSports.isEmpty ? [.running] : model.selectedSports
    }

    var body: some View {
        OnboardingStep(primary: model.advance) {
            OnboardingHeader(
                title: "Your first kit",
                subtitle: "Start with a clean performance setup. More pieces unlock from real training."
            )

            if availableSports.count > 1 {
                Picker("Sport", selection: $selectedSport) {
                    ForEach(availableSports, id: \.self) { sport in
                        Text(sport.displayName).tag(sport)
                    }
                }
                .pickerStyle(.segmented)
            }

            AthleteAvatarView(
                avatar: model.avatar,
                sport: selectedSport,
                size: 330
            )
            .frame(maxWidth: .infinity)
            .frame(height: 350)
            .background(
                LinearGradient(
                    colors: [
                        selectedSport.discipline.themedTint(theme).opacity(0.14),
                        theme.color(.surface, classic: Color(uiColor: .systemBackground))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: .rect(cornerRadius: 28)
            )

            VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(text: "Included")
                ForEach(AvatarGearCatalog.items(for: selectedSport).filter(\.isStarterUnlocked)) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.title3)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                            Text("Starter gear")
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(selectedSport.discipline.themedTint(theme))
                    }
                    .padding(14)
                    .background(
                        theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
                        in: .rect(cornerRadius: 16)
                    )
                }
            }
        }
        .onAppear {
            if let first = availableSports.first {
                selectedSport = first
            }
        }
    }
}

struct AthleteAvatarReadyStepView: View {
    @Environment(\.atheviaTheme) private var theme
    @Bindable var model: OnboardingModel

    private var primarySport: Sport {
        model.selectedSports.first ?? .running
    }

    var body: some View {
        OnboardingStep(primaryTitle: "Continue setup", primary: model.advance) {
            VStack(spacing: 22) {
                OnboardingHeader(
                    title: "Your athlete is ready",
                    subtitle: "This is the starting point. Your gear collection grows as your real training history grows."
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.06, green: 0.08, blue: 0.13),
                                    Color(red: 0.015, green: 0.02, blue: 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    AthleteAvatarView(
                        avatar: model.avatar,
                        sport: primarySport,
                        size: 330
                    )
                }
                .frame(height: 390)
                .clipShape(.rect(cornerRadius: 30))

                VStack(alignment: .leading, spacing: 10) {
                    rewardRow(
                        icon: "shoe.fill",
                        title: "First workout",
                        detail: "Your first earned gear reward"
                    )
                    rewardRow(
                        icon: "tshirt.fill",
                        title: "Build consistency",
                        detail: "Unlock performance pieces from completed training"
                    )
                    rewardRow(
                        icon: "medal.fill",
                        title: "Reach milestones",
                        detail: "Milestone pieces mark what you have actually achieved"
                    )
                }

                Text("Cosmetic rewards never change your training plan or capability rating.")
                    .font(.footnote)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func rewardRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(
                    theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            theme.color(.surface, classic: Color(uiColor: .secondarySystemBackground)),
            in: .rect(cornerRadius: 16)
        )
    }
}
