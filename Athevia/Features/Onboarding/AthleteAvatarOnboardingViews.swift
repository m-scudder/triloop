import SwiftUI

private struct AthleteOnboardingHero<Overlay: View>: View {
    let avatar: AthleteAvatar
    let sport: Sport
    var pose: AvatarPose = .neutral
    var height: CGFloat = 440
    @ViewBuilder var overlay: Overlay

    @Environment(\.atheviaTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            sport.discipline.themedTint(theme).opacity(0.30),
                            Color(red: 0.075, green: 0.105, blue: 0.16),
                            Color(red: 0.018, green: 0.028, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(sport.discipline.themedTint(theme).opacity(0.20))
                .frame(width: 280, height: 280)
                .blur(radius: 28)
                .offset(x: 100, y: -110)

            AthleteAvatarView(
                avatar: avatar,
                sport: sport,
                pose: pose,
                size: height * 0.90
            )
            .frame(maxWidth: .infinity)
            .frame(height: height - 28)

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: 30))

            overlay
                .padding(20)
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 26, y: 14)
    }
}

struct AthleteAvatarIntroStepView: View {
    @Bindable var model: OnboardingModel

    private var primarySport: Sport {
        model.selectedSports.first ?? .running
    }

    var body: some View {
        OnboardingStep(primaryTitle: "Create my athlete", primary: model.advance) {
            VStack(spacing: 18) {
                AthleteOnboardingHero(
                    avatar: model.avatar,
                    sport: primarySport,
                    height: 500
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ATHEVIA")
                            .font(.caption.weight(.bold))
                            .tracking(2.2)
                            .foregroundStyle(.white.opacity(0.70))

                        Text("Build your athlete")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)

                        Text("Train. Progress. Become.")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.82))

                        Text("Your athlete evolves from real training, milestones and earned gear.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    valuePill("figure.run", "Train")
                    valuePill("medal.fill", "Progress")
                    valuePill("tshirt.fill", "Unlock")
                }
            }
        }
    }

    private func valuePill(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(AtheviaAdaptiveStyle(.background.secondary, gaming: .surface), in: .capsule)
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

    var body: some View {
        OnboardingStep(primary: model.advance) {
            OnboardingHeader(
                title: "Customize appearance",
                subtitle: "Your athlete, your journey."
            )

            AthleteOnboardingHero(
                avatar: model.avatar,
                sport: primarySport,
                height: 390
            ) {
                HStack {
                    Text(model.avatar.presentation.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(model.avatar.bodyPreset.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            VStack(spacing: 18) {
                Picker("Presentation", selection: binding.presentation) {
                    ForEach(AvatarPresentation.allCases) { presentation in
                        Text(presentation.displayName).tag(presentation)
                    }
                }
                .pickerStyle(.segmented)

                appearanceSection("Skin tone") {
                    HStack(spacing: 12) {
                        ForEach(AvatarSkinTone.allCases) { tone in
                            skinToneButton(tone)
                        }
                    }
                }

                appearanceSection("Hair") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
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
                    }
                }

                appearanceSection("Build") {
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
    }

    private func appearanceSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(width: 38, height: 38)
                .overlay {
                    if model.avatar.skinTone == tone {
                        Circle()
                            .stroke(theme.color(.accent, classic: .blue), lineWidth: 3)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 42)
                .background(
                    selected
                        ? theme.color(.accent, classic: .blue)
                        : theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
                    in: .capsule
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
                title: "Your starter kit",
                subtitle: "Start here and unlock new equipment as you train."
            )

            if availableSports.count > 1 {
                Picker("Sport", selection: $selectedSport) {
                    ForEach(availableSports, id: \.self) { sport in
                        Text(sport.displayName).tag(sport)
                    }
                }
                .pickerStyle(.segmented)
            }

            AthleteOnboardingHero(
                avatar: model.avatar,
                sport: selectedSport,
                height: 430
            ) {
                HStack {
                    Text(selectedSport.displayName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Label("Starter kit", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            VStack(spacing: 10) {
                ForEach(AvatarGearCatalog.items(for: selectedSport).filter(\.isStarterUnlocked)) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.title3)
                            .frame(width: 42, height: 42)
                            .background(
                                selectedSport.discipline.themedTint(theme).opacity(0.12),
                                in: .rect(cornerRadius: 13)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                            Text(item.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(selectedSport.discipline.themedTint(theme))
                    }
                    .padding(14)
                    .background(
                        theme.color(.surface, classic: Color(uiColor: .secondarySystemBackground)),
                        in: .rect(cornerRadius: 18)
                    )
                }
            }
        }
        .onAppear {
            selectedSport = availableSports.first ?? .running
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
        OnboardingStep(primaryTitle: "Let's go", primary: model.advance) {
            VStack(spacing: 18) {
                AthleteOnboardingHero(
                    avatar: model.avatar,
                    sport: primarySport,
                    pose: .neutral,
                    height: 500
                ) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("YOUR ATHLETE IS READY")
                            .font(.caption.weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.66))

                        Text("Train. Unlock gear. Reach your goals.")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                rewardRow(
                    icon: "trophy.fill",
                    title: "Complete your first workout",
                    detail: "Unlock new training gear"
                )
                rewardRow(
                    icon: "chart.bar.fill",
                    title: "Build consistency",
                    detail: "Unlock performance items"
                )
                rewardRow(
                    icon: "medal.fill",
                    title: "Reach milestones",
                    detail: "Earn special rewards"
                )
            }
        }
    }

    private func rewardRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(theme.color(.accent, classic: .blue))
                .frame(width: 44, height: 44)
                .background(
                    theme.color(.accent, classic: .blue).opacity(0.10),
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            theme.color(.surface, classic: Color(uiColor: .secondarySystemBackground)),
            in: .rect(cornerRadius: 18)
        )
    }
}
