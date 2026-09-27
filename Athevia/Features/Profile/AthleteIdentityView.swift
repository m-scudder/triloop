import SwiftUI

private enum AthleteProfileTab: String, CaseIterable, Identifiable {
    case overview
    case stats
    case milestones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .stats: "Stats"
        case .milestones: "Milestones"
        }
    }
}

struct AthleteIdentityView: View {
    @Environment(\.atheviaTheme) private var theme
    @Binding var avatar: AthleteAvatar
    var athleteName: String = "Your Athlete"
    var selectedSports: [Sport]
    var plans: [WeeklyPlan]
    var setup: AthleteSetup

    @State private var selectedSport: Sport = .running
    @State private var selectedTab: AthleteProfileTab = .overview

    private var sports: [Sport] {
        selectedSports.isEmpty ? [.running] : selectedSports
    }

    private var rewards: AvatarRewardSnapshot {
        AvatarRewardEvaluator().evaluate(setup: setup, plans: plans)
    }

    private var journey: TrainingJourney {
        TrainingJourneyPlanner().plan(
            setup: setup,
            recentPlans: Array(plans.prefix(4))
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                tabBar
                hero
                sportBar

                switch selectedTab {
                case .overview:
                    overviewContent
                case .stats:
                    statsContent
                case .milestones:
                    milestoneContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
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
        .navigationTitle("My Athlete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.015, green: 0.025, blue: 0.045), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if !sports.contains(selectedSport), let first = sports.first {
                selectedSport = first
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AthleteProfileTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selectedTab == tab ? Color.white.opacity(0.13) : .clear,
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.055), in: .capsule)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Image("AthleteProfileAlpineBackground")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    selectedSport.discipline.themedTint(theme).opacity(0.10),
                    .clear,
                    Color.black.opacity(0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            AthleteAvatarView(
                avatar: avatar,
                sport: selectedSport,
                pose: .neutral,
                size: 420
            )
            .frame(maxWidth: .infinity)
            .frame(height: 405)
            .offset(y: -2)

            LinearGradient(
                colors: [.clear, .black.opacity(0.76)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: 30))

            VStack(alignment: .leading, spacing: 4) {
                Text(athleteName.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.62))

                Text(journey.phase.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text("Level \(max(1, rewards.milestones.count + 1))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))

                    ProgressView(
                        value: Double(min(rewards.milestones.count, 5)),
                        total: 5
                    )
                    .tint(selectedSport.discipline.themedTint(theme))
                    .frame(maxWidth: 120)
                }
            }
            .padding(20)
        }
        .frame(height: 440)
        .clipShape(.rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 28, y: 16)
    }

    @ViewBuilder
    private var sportBar: some View {
        if sports.count > 1 {
            Picker("Sport", selection: $selectedSport) {
                ForEach(sports, id: \.self) { sport in
                    Text(sport.displayName).tag(sport)
                }
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)
        }
    }

    private var overviewContent: some View {
        VStack(spacing: 16) {
            progressCard

            NavigationLink {
                AthleteAvatarStudioView(
                    avatar: $avatar,
                    selectedSports: sports
                )
            } label: {
                Label("Customize athlete", systemImage: "person.crop.square")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())

            HStack(spacing: 12) {
                NavigationLink {
                    AthleteWardrobeView(
                        avatar: $avatar,
                        sports: sports,
                        initialSport: selectedSport,
                        rewards: rewards
                    )
                } label: {
                    dashboardTile(
                        symbol: "tshirt.fill",
                        title: "Wardrobe",
                        detail: "\(rewards.unlockedGearIDs.count) pieces"
                    )
                }

                NavigationLink {
                    AthleteRewardJourneyView(
                        sports: sports,
                        rewards: rewards
                    )
                } label: {
                    dashboardTile(
                        symbol: "medal.fill",
                        title: "Rewards",
                        detail: "\(rewards.milestones.count) milestones"
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var statsContent: some View {
        VStack(spacing: 14) {
            progressCard

            VStack(spacing: 0) {
                statRow("Running", value: "\(rewards.runningCompleted) workouts")
                Divider().overlay(.white.opacity(0.08))
                statRow("Cycling", value: "\(rewards.cyclingCompleted) workouts")
                Divider().overlay(.white.opacity(0.08))
                statRow("Swimming", value: "\(rewards.swimmingCompleted) workouts")
            }
            .padding(.horizontal, 16)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 20))
        }
    }

    private var milestoneContent: some View {
        VStack(spacing: 12) {
            if rewards.milestones.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "medal")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Your milestones will appear here")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Complete real training and Athevia will record the evidence automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(.white.opacity(0.055), in: .rect(cornerRadius: 22))
            } else {
                ForEach(rewards.milestones.prefix(8)) { milestone in
                    HStack(spacing: 14) {
                        Image(systemName: "medal.fill")
                            .font(.title3)
                            .foregroundStyle(selectedSport.discipline.themedTint(theme))
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.07), in: .circle)

                        Text(milestone.kind.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .padding(14)
                    .background(.white.opacity(0.055), in: .rect(cornerRadius: 18))
                }
            }
        }
    }

    private func dashboardTile(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(selectedSport.discipline.themedTint(theme))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 20))
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.64))
        }
        .padding(.vertical, 15)
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
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private var progressCard: some View {
        HStack(spacing: 0) {
            metric(
                value: "\(rewards.unlockedGearIDs.count)",
                label: "Gear unlocked"
            )
            Divider().frame(height: 38).overlay(.white.opacity(0.10))
            metric(
                value: "\(rewards.milestones.count)",
                label: "Milestones"
            )
            Divider().frame(height: 38)
            metric(
                value: "\(rewards.runningCompleted + rewards.cyclingCompleted + rewards.swimmingCompleted)",
                label: "Workouts"
            )
        }
        .padding(.vertical, 16)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 20))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
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
    let rewards: AvatarRewardSnapshot

    @State private var selectedSport: Sport
    @State private var selectedCategory: AvatarGearCategory = .top

    init(
        avatar: Binding<AthleteAvatar>,
        sports: [Sport],
        initialSport: Sport,
        rewards: AvatarRewardSnapshot
    ) {
        _avatar = avatar
        self.sports = sports
        self.initialSport = initialSport
        self.rewards = rewards
        _selectedSport = State(initialValue: initialSport)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var visibleItems: [AvatarGearItem] {
        AvatarGearCatalog.items(for: selectedSport)
            .filter { $0.category == selectedCategory }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    AthleteAvatarView(
                        avatar: avatar,
                        sport: selectedSport,
                        size: 92
                    )
                    .frame(width: 70, height: 82)
                    .clipped()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR WARDROBE")
                            .font(.caption2.weight(.bold))
                            .tracking(1.3)
                            .foregroundStyle(.white.opacity(0.52))
                        Text("Equip what you've earned")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(rewards.unlockedGearIDs.count) pieces unlocked")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer()
                }
                .padding(14)
                .background(.white.opacity(0.055), in: .rect(cornerRadius: 20))

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
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
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
        .navigationTitle("Wardrobe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.015, green: 0.025, blue: 0.045), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            VStack(spacing: 5) {
                Image(systemName: categorySymbol(category))
                    .font(.subheadline.weight(.semibold))
                Text(category.displayName)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selected ? .white : .white.opacity(0.60))
            .frame(width: 72, height: 54)
            .background(
                selected
                    ? theme.color(.accent, classic: .blue)
                    : Color.white.opacity(0.055),
                in: .rect(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    private func categorySymbol(_ category: AvatarGearCategory) -> String {
        switch category {
        case .top: "tshirt.fill"
        case .bottom: "figure.walk"
        case .footwear: "shoe.fill"
        case .headwear: "baseballcap.fill"
        case .accessory: "eyeglasses"
        }
    }

    private func gearCard(_ item: AvatarGearItem) -> some View {
        let equipped = isEquipped(item)
        let unlocked = rewards.isUnlocked(item)

        return NavigationLink {
            AthleteGearDetailView(
                avatar: $avatar,
                item: item,
                sport: selectedSport,
                rewards: rewards
            )
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

                    gearArtwork(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !unlocked {
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
                .frame(height: 116)
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

                    Text(equipped ? "Equipped" : rewards.progressText(for: item))
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
            .padding(8)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gearArtwork(_ item: AvatarGearItem) -> some View {
        switch item.id {
        case .runTopIvory:
            Image("AvatarGearRunTopIvory")
                .resizable()
                .scaledToFit()
                .padding(10)
        case .runShoeCobalt:
            Image("AvatarGearRunShoeCobalt")
                .resizable()
                .scaledToFit()
                .padding(8)
        default:
            Image(systemName: item.symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(
                    rewards.isUnlocked(item) ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
                )
        }
    }

    private func isEquipped(_ item: AvatarGearItem) -> Bool {
        let loadout = avatar.loadout(for: selectedSport)
        switch item.category {
        case .top: return loadout.top == item.id
        case .bottom: return loadout.bottom == item.id
        case .footwear: return loadout.footwear == item.id
        case .headwear: return loadout.headwear == item.id
        case .accessory: return loadout.accessory == item.id
        }
    }
}

struct AthleteGearDetailView: View {
    @Environment(\.atheviaTheme) private var theme
    @Binding var avatar: AthleteAvatar

    let item: AvatarGearItem
    let sport: Sport
    let rewards: AvatarRewardSnapshot

    private var unlocked: Bool {
        rewards.isUnlocked(item)
    }

    private var equipped: Bool {
        let loadout = avatar.loadout(for: sport)
        switch item.category {
        case .top: return loadout.top == item.id
        case .bottom: return loadout.bottom == item.id
        case .footwear: return loadout.footwear == item.id
        case .headwear: return loadout.headwear == item.id
        case .accessory: return loadout.accessory == item.id
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                artwork

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name)
                        .font(.title2.weight(.bold))

                    Text(item.category.displayName)
                        .font(.subheadline)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                requirementCard

                Button(equipped ? "Equipped" : (unlocked ? "Equip" : "Locked")) {
                    avatar.equip(item, isUnlocked: unlocked)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!unlocked || equipped)
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.025, blue: 0.045),
                    Color(red: 0.03, green: 0.05, blue: 0.085)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Gear")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(red: 0.015, green: 0.025, blue: 0.045), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var artwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    sport.discipline.themedTint(theme).opacity(0.15),
                    theme.color(.surface, classic: Color(uiColor: .secondarySystemBackground))
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            detailArtwork
                .padding(24)
        }
        .frame(height: 380)
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(
                    theme.color(.border, classic: Color.secondary.opacity(0.14)),
                    lineWidth: 0.5
                )
        }
    }

    @ViewBuilder
    private var detailArtwork: some View {
        switch item.id {
        case .runTopIvory:
            Image("AvatarGearRunTopIvory")
                .resizable()
                .scaledToFit()
        case .runShoeCobalt:
            Image("AvatarGearRunShoeCobalt")
                .resizable()
                .scaledToFit()
        default:
            Image(systemName: item.symbol)
                .font(.system(size: 90, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var requirementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: unlocked ? "Unlocked" : "Unlock requirement")

            Text(item.unlockText)
                .font(.headline)

            Text(rewards.progressText(for: item))
                .font(.subheadline)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))

            if case .completedSportWorkouts(let sport, let required) = item.unlockRule {
                let completed = rewards.completedCount(for: sport)
                ProgressView(
                    value: Double(min(completed, required)),
                    total: Double(required)
                )
                .tint(sport.discipline.themedTint(theme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            theme.color(.surface, classic: Color(uiColor: .secondarySystemBackground)),
            in: .rect(cornerRadius: 20)
        )
    }
}

struct AthleteRewardJourneyView: View {
    let sports: [Sport]
    let rewards: AvatarRewardSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeader(
                    title: "Earned, not bought",
                    subtitle: "Rewards unlock from completed training and verified milestones. Nothing here changes your training plan."
                )

                ForEach(rewardItems) { item in
                    let unlocked = rewards.isUnlocked(item)

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
                            Text(rewards.progressText(for: item))
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        }

                        Spacer(minLength: 8)

                        if unlocked {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
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
