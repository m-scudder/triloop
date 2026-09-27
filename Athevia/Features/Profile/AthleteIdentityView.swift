import SwiftUI

struct AthleteIdentityView: View {
    @Environment(\.atheviaTheme) private var theme
    @Binding var avatar: AthleteAvatar
    var selectedSports: [Sport]

    @State private var selectedSport: Sport = .running

    private var sports: [Sport] {
        selectedSports.isEmpty ? [.running] : selectedSports
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero

                if sports.count > 1 {
                    Picker("Sport", selection: $selectedSport) {
                        ForEach(sports, id: \.self) { sport in
                            Text(sport.displayName).tag(sport)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Card {
                    VStack(spacing: 0) {
                        NavigationLink {
                            AthleteAvatarStudioView(
                                avatar: $avatar,
                                selectedSports: sports
                            )
                        } label: {
                            identityRow(
                                symbol: "person.crop.square",
                                title: "Appearance",
                                detail: "Face, hair, skin tone and build"
                            )
                        }

                        Divider().padding(.leading, 46)

                        NavigationLink {
                            AthleteWardrobeView(
                                avatar: $avatar,
                                sports: sports,
                                initialSport: selectedSport
                            )
                        } label: {
                            identityRow(
                                symbol: "tshirt.fill",
                                title: "Wardrobe",
                                detail: "Equip earned training gear"
                            )
                        }

                        Divider().padding(.leading, 46)

                        NavigationLink {
                            AthleteRewardJourneyView(sports: sports)
                        } label: {
                            identityRow(
                                symbol: "medal.fill",
                                title: "Reward journey",
                                detail: "See what your training can unlock"
                            )
                        }
                    }
                }

                philosophyCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .atheviaScreen()
        .navigationTitle("My Athlete")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !sports.contains(selectedSport), let first = sports.first {
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
                            Color(red: 0.055, green: 0.075, blue: 0.12),
                            Color(red: 0.015, green: 0.02, blue: 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(selectedSport.discipline.themedTint(theme).opacity(0.16))
                .frame(width: 230, height: 230)
                .blur(radius: 8)
                .offset(x: 80, y: -90)

            VStack(spacing: 8) {
                AthleteAvatarView(avatar: avatar, sport: selectedSport, size: 330)
                    .frame(height: 330)

                Text(selectedSport.displayName.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))

                Text("Your athlete")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 18)
            }
        }
        .frame(height: 420)
        .clipShape(.rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
    }

    private func identityRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 32, height: 32)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private var philosophyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: "How it grows")
            Text("Gear is earned from completed training, consistency and real milestones.")
                .font(.subheadline.weight(.semibold))
            Text("Rest and recovery never count against your athlete, and cosmetic rewards never change your plan.")
                .font(.footnote)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            theme.color(.surface, classic: Color(uiColor: .secondarySystemBackground)),
            in: .rect(cornerRadius: 20)
        )
    }
}

struct AthleteWardrobeView: View {
    @Environment(\.atheviaTheme) private var theme
    @Binding var avatar: AthleteAvatar
    let sports: [Sport]
    let initialSport: Sport

    @State private var selectedSport: Sport
    @State private var selectedCategory: AvatarGearCategory = .top

    init(
        avatar: Binding<AthleteAvatar>,
        sports: [Sport],
        initialSport: Sport
    ) {
        _avatar = avatar
        self.sports = sports
        self.initialSport = initialSport
        _selectedSport = State(initialValue: initialSport)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var visibleItems: [AvatarGearItem] {
        AvatarGearCatalog.items(for: selectedSport)
            .filter { $0.category == selectedCategory }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AthleteAvatarView(
                    avatar: avatar,
                    sport: selectedSport,
                    size: 270
                )
                .frame(maxWidth: .infinity)
                .frame(height: 290)
                .background(
                    LinearGradient(
                        colors: [
                            selectedSport.discipline.themedTint(theme).opacity(0.13),
                            theme.color(.surface, classic: Color(uiColor: .systemBackground))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: .rect(cornerRadius: 26)
                )

                if sports.count > 1 {
                    Picker("Sport", selection: $selectedSport) {
                        ForEach(sports, id: \.self) { sport in
                            Text(sport.displayName).tag(sport)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCategories, id: \.self) { category in
                            categoryChip(category)
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visibleItems) { item in
                        gearCard(item)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .atheviaScreen()
        .navigationTitle("Wardrobe")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedSport) { _, _ in
            if !availableCategories.contains(selectedCategory) {
                selectedCategory = availableCategories.first ?? .top
            }
        }
    }

    private var availableCategories: [AvatarGearCategory] {
        let present = Set(AvatarGearCatalog.items(for: selectedSport).map(\.category))
        return AvatarGearCategory.allCases.filter(present.contains)
    }

    private func categoryChip(_ category: AvatarGearCategory) -> some View {
        let selected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(category.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? theme.color(.onAccent, classic: .white) : .primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(
                    selected
                        ? theme.color(.accent, classic: .blue)
                        : theme.color(.raisedSurface, classic: Color(uiColor: .secondarySystemBackground)),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
    }

    private func gearCard(_ item: AvatarGearItem) -> some View {
        let equipped = isEquipped(item)

        return Button {
            guard item.isStarterUnlocked else { return }
            avatar.equip(item)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            theme.color(
                                .raisedSurface,
                                classic: Color(uiColor: .tertiarySystemBackground)
                            )
                        )

                    Image(systemName: item.symbol)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(
                            item.isStarterUnlocked ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
                        )

                    if !item.isStarterUnlocked {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: .circle)
                            }
                            Spacer()
                        }
                        .padding(8)
                    }
                }
                .frame(height: 122)
                .overlay {
                    if equipped {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(selectedSport.discipline.themedTint(theme), lineWidth: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(equipped ? "Equipped" : item.unlockText)
                        .font(.caption)
                        .foregroundStyle(
                            equipped
                                ? selectedSport.discipline.themedTint(theme)
                                : theme.color(.secondaryText, classic: Color.secondary)
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(
                theme.color(.surface, classic: Color(uiColor: .secondarySystemBackground)),
                in: .rect(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
        .disabled(!item.isStarterUnlocked)
    }

    private func isEquipped(_ item: AvatarGearItem) -> Bool {
        let loadout = avatar.loadout(for: selectedSport)
        switch item.category {
        case .top: return loadout.top == item.id
        case .bottom: return loadout.bottom == item.id
        case .footwear: return loadout.footwear == item.id
        case .headwear: return loadout.headwear == item.id
        case .accessory: return false
        }
    }
}

struct AthleteRewardJourneyView: View {
    let sports: [Sport]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeader(
                    title: "Earned, not bought",
                    subtitle: "The first reward set is tied to real training evidence. These are previews; unlock evaluation comes next."
                )

                ForEach(rewardItems) { item in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface))
                                .frame(width: 56, height: 56)
                            Image(systemName: item.symbol)
                                .font(.title3)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                            Text(item.unlockText)
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        }

                        Spacer(minLength: 8)

                        if !item.isStarterUnlocked {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(14)
                    .background(
                        AtheviaAdaptiveStyle(.background.secondary, gaming: .surface),
                        in: .rect(cornerRadius: 18)
                    )
                }
            }
            .padding(20)
        }
        .atheviaScreen()
        .navigationTitle("Reward Journey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rewardItems: [AvatarGearItem] {
        let selected = Set(sports)
        return AvatarGearCatalog.items.filter { item in
            guard let sport = item.sport else { return true }
            return selected.contains(sport) && !item.isStarterUnlocked
        }
    }
}
