import Foundation

/// Cosmetic identity for the athlete. This state never participates in training
/// decisions, capability evaluation, progression, or safety logic.
struct AthleteAvatar: Codable, Equatable, Sendable {
    var presentation: AvatarPresentation = .feminine
    var skinTone: AvatarSkinTone = .warmMedium
    var hairStyle: AvatarHairStyle = .swept
    var hairColor: AvatarHairColor = .espresso
    var bodyPreset: AvatarBodyPreset = .balanced
    var runLoadout: AvatarLoadout = .starterRun
    var cycleLoadout: AvatarLoadout = .starterCycle
    var swimLoadout: AvatarLoadout = .starterSwim

    static let starter = AthleteAvatar()

    func loadout(for sport: Sport) -> AvatarLoadout {
        switch sport {
        case .running: runLoadout
        case .cycling: cycleLoadout
        case .swimming: swimLoadout
        }
    }

    mutating func equip(_ item: AvatarGearItem, isUnlocked: Bool) {
        guard isUnlocked else { return }

        switch item.sport {
        case .running:
            Self.apply(item.id, category: item.category, to: &runLoadout)
        case .cycling:
            Self.apply(item.id, category: item.category, to: &cycleLoadout)
        case .swimming:
            Self.apply(item.id, category: item.category, to: &swimLoadout)
        case nil:
            break
        }
    }

    private static func apply(_ id: AvatarGearID, category: AvatarGearCategory, to loadout: inout AvatarLoadout) {
        switch category {
        case .top: loadout.top = id
        case .bottom: loadout.bottom = id
        case .footwear: loadout.footwear = id
        case .headwear: loadout.headwear = id
        case .accessory: break
        }
    }
}

enum AvatarGearCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case top
    case bottom
    case footwear
    case headwear
    case accessory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: "Tops"
        case .bottom: "Bottoms"
        case .footwear: "Footwear"
        case .headwear: "Headwear"
        case .accessory: "Accessories"
        }
    }
}

enum AvatarUnlockRule: Equatable, Sendable {
    case starter
    case completedSportWorkouts(Sport, Int)
    case milestone(JourneyMilestoneKind)

    var description: String {
        switch self {
        case .starter:
            "Starter gear"
        case .completedSportWorkouts(let sport, let count):
            "Complete \(count) \(sport.displayName.lowercased()) workout\(count == 1 ? "" : "s")"
        case .milestone(let kind):
            kind.displayName
        }
    }
}

struct AvatarGearItem: Identifiable, Equatable, Sendable {
    let id: AvatarGearID
    let name: String
    let category: AvatarGearCategory
    let sport: Sport?
    let symbol: String
    let unlockRule: AvatarUnlockRule

    var unlockText: String { unlockRule.description }
    var isStarterUnlocked: Bool {
        if case .starter = unlockRule { return true }
        return false
    }
}

struct AvatarRewardSnapshot: Equatable, Sendable {
    let unlockedGearIDs: Set<AvatarGearID>
    let runningCompleted: Int
    let cyclingCompleted: Int
    let swimmingCompleted: Int
    let milestones: [JourneyMilestone]

    func isUnlocked(_ item: AvatarGearItem) -> Bool {
        unlockedGearIDs.contains(item.id)
    }

    func completedCount(for sport: Sport) -> Int {
        switch sport {
        case .running: runningCompleted
        case .cycling: cyclingCompleted
        case .swimming: swimmingCompleted
        }
    }

    func progressText(for item: AvatarGearItem) -> String {
        switch item.unlockRule {
        case .starter:
            "Unlocked"
        case .completedSportWorkouts(let sport, let required):
            "\(min(completedCount(for: sport), required)) / \(required) workouts"
        case .milestone(let kind):
            milestones.contains(where: { $0.kind == kind }) ? "Unlocked" : kind.displayName
        }
    }
}

struct AvatarRewardEvaluator: Sendable {
    func evaluate(
        setup: AthleteSetup,
        plans: [WeeklyPlan],
        asOf date: Date = .now
    ) -> AvatarRewardSnapshot {
        let completed = plans
            .flatMap(\.trainingSessions)
            .filter(\.isCompleted)

        let runCount = completed.filter { $0.discipline.sport == .running }.count
        let cycleCount = completed.filter { $0.discipline.sport == .cycling }.count
        let swimCount = completed.filter { $0.discipline.sport == .swimming }.count
        let milestones = JourneyProgressBuilder().milestones(
            setup: setup,
            plans: plans,
            asOf: date
        )

        var unlocked = Set<AvatarGearID>()
        for item in AvatarGearCatalog.items {
            if isSatisfied(
                item.unlockRule,
                runCount: runCount,
                cycleCount: cycleCount,
                swimCount: swimCount,
                milestones: milestones
            ) {
                unlocked.insert(item.id)
            }
        }

        return AvatarRewardSnapshot(
            unlockedGearIDs: unlocked,
            runningCompleted: runCount,
            cyclingCompleted: cycleCount,
            swimmingCompleted: swimCount,
            milestones: milestones
        )
    }

    private func isSatisfied(
        _ rule: AvatarUnlockRule,
        runCount: Int,
        cycleCount: Int,
        swimCount: Int,
        milestones: [JourneyMilestone]
    ) -> Bool {
        switch rule {
        case .starter:
            true
        case .completedSportWorkouts(let sport, let required):
            let actual: Int
            switch sport {
            case .running: actual = runCount
            case .cycling: actual = cycleCount
            case .swimming: actual = swimCount
            }
            return actual >= required
        case .milestone(let kind):
            return milestones.contains { $0.kind == kind }
        }
    }
}

enum AvatarGearCatalog {
    static let items: [AvatarGearItem] = [
        .init(id: .runTopGraphite, name: "Graphite Run Top", category: .top, sport: .running, symbol: "tshirt.fill", unlockRule: .starter),
        .init(id: .runTopIvory, name: "Ivory Performance Top", category: .top, sport: .running, symbol: "tshirt", unlockRule: .completedSportWorkouts(.running, 3)),
        .init(id: .runTopCobalt, name: "Cobalt Tempo Top", category: .top, sport: .running, symbol: "tshirt.fill", unlockRule: .milestone(.firstCompleteTrainingWeek)),
        .init(id: .runShortBlack, name: "Run Short — Black", category: .bottom, sport: .running, symbol: "figure.run", unlockRule: .starter),
        .init(id: .runShortSlate, name: "Run Short — Slate", category: .bottom, sport: .running, symbol: "figure.run", unlockRule: .completedSportWorkouts(.running, 5)),
        .init(id: .runShoeWhite, name: "Foundation Runner", category: .footwear, sport: .running, symbol: "shoe.fill", unlockRule: .starter),
        .init(id: .runShoeCobalt, name: "Tempo Runner", category: .footwear, sport: .running, symbol: "shoe.fill", unlockRule: .milestone(.firstFiveK)),
        .init(id: .runCapBlack, name: "Training Cap", category: .headwear, sport: .running, symbol: "baseball.cap.fill", unlockRule: .milestone(.firstCompleteTrainingWeek)),

        .init(id: .cycleJerseyGraphite, name: "Graphite Cycle Jersey", category: .top, sport: .cycling, symbol: "tshirt.fill", unlockRule: .starter),
        .init(id: .cycleJerseyCobalt, name: "Cobalt Endurance Jersey", category: .top, sport: .cycling, symbol: "tshirt.fill", unlockRule: .completedSportWorkouts(.cycling, 5)),
        .init(id: .cycleBibBlack, name: "Cycle Bib — Black", category: .bottom, sport: .cycling, symbol: "bicycle", unlockRule: .starter),
        .init(id: .cycleShoeBlack, name: "Road Shoe — Black", category: .footwear, sport: .cycling, symbol: "shoe.fill", unlockRule: .starter),
        .init(id: .cycleHelmetBlack, name: "Road Helmet — Black", category: .headwear, sport: .cycling, symbol: "bicycle.helmet", unlockRule: .starter),
        .init(id: .cycleHelmetWhite, name: "Road Helmet — White", category: .headwear, sport: .cycling, symbol: "bicycle.helmet", unlockRule: .completedSportWorkouts(.cycling, 4)),

        .init(id: .swimSuitGraphite, name: "Graphite Swim Kit", category: .top, sport: .swimming, symbol: "figure.pool.swim", unlockRule: .starter),
        .init(id: .swimSuitCobalt, name: "Cobalt Swim Kit", category: .top, sport: .swimming, symbol: "figure.pool.swim", unlockRule: .completedSportWorkouts(.swimming, 5)),
        .init(id: .swimCapBlack, name: "Swim Cap — Black", category: .headwear, sport: .swimming, symbol: "drop.fill", unlockRule: .starter),
        .init(id: .swimCapWhite, name: "Swim Cap — White", category: .headwear, sport: .swimming, symbol: "drop", unlockRule: .completedSportWorkouts(.swimming, 3)),
        .init(id: .swimGogglesSmoke, name: "Smoke Goggles", category: .accessory, sport: .swimming, symbol: "eyeglasses", unlockRule: .milestone(.swim100Continuous))
    ]

    static func items(for sport: Sport) -> [AvatarGearItem] {
        items.filter { $0.sport == sport }
    }

    static func item(_ id: AvatarGearID) -> AvatarGearItem? {
        items.first { $0.id == id }
    }
}

enum AvatarPresentation: String, Codable, CaseIterable, Identifiable, Sendable {
    case feminine
    case masculine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .feminine: "Feminine"
        case .masculine: "Masculine"
        }
    }
}

enum AvatarSkinTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case warmLight
    case warmMedium
    case medium
    case deep
    case rich

    var id: String { rawValue }

    /// Stable RGB values keep the SwiftUI renderer deterministic.
    var rgb: (Double, Double, Double) {
        switch self {
        case .light: (0.94, 0.78, 0.67)
        case .warmLight: (0.86, 0.66, 0.52)
        case .warmMedium: (0.73, 0.49, 0.34)
        case .medium: (0.58, 0.37, 0.25)
        case .deep: (0.39, 0.24, 0.17)
        case .rich: (0.24, 0.14, 0.10)
        }
    }
}

enum AvatarHairStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case cropped
    case swept
    case tied
    case textured
    case long
    case closeCut

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cropped: "Cropped"
        case .swept: "Swept"
        case .tied: "Tied"
        case .textured: "Textured"
        case .long: "Long"
        case .closeCut: "Close cut"
        }
    }
}

enum AvatarHairColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case midnight
    case espresso
    case chestnut
    case copper
    case sand
    case silver

    var id: String { rawValue }

    var rgb: (Double, Double, Double) {
        switch self {
        case .midnight: (0.05, 0.05, 0.07)
        case .espresso: (0.15, 0.08, 0.05)
        case .chestnut: (0.30, 0.14, 0.08)
        case .copper: (0.52, 0.20, 0.09)
        case .sand: (0.67, 0.50, 0.28)
        case .silver: (0.55, 0.56, 0.60)
        }
    }
}

enum AvatarBodyPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case lean
    case balanced
    case powerful

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lean: "Lean"
        case .balanced: "Balanced"
        case .powerful: "Powerful"
        }
    }

    var shoulderScale: Double {
        switch self {
        case .lean: 0.90
        case .balanced: 1.0
        case .powerful: 1.10
        }
    }
}

struct AvatarLoadout: Codable, Equatable, Sendable {
    var top: AvatarGearID
    var bottom: AvatarGearID
    var footwear: AvatarGearID
    var headwear: AvatarGearID?

    static let starterRun = AvatarLoadout(
        top: .runTopGraphite,
        bottom: .runShortBlack,
        footwear: .runShoeWhite,
        headwear: nil
    )

    static let starterCycle = AvatarLoadout(
        top: .cycleJerseyGraphite,
        bottom: .cycleBibBlack,
        footwear: .cycleShoeBlack,
        headwear: .cycleHelmetBlack
    )

    static let starterSwim = AvatarLoadout(
        top: .swimSuitGraphite,
        bottom: .swimSuitGraphite,
        footwear: .barefoot,
        headwear: .swimCapBlack
    )
}

enum AvatarGearID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case runTopGraphite
    case runTopIvory
    case runTopCobalt
    case runShortBlack
    case runShortSlate
    case runShoeWhite
    case runShoeCobalt
    case runCapBlack

    case cycleJerseyGraphite
    case cycleJerseyCobalt
    case cycleBibBlack
    case cycleShoeBlack
    case cycleHelmetBlack
    case cycleHelmetWhite

    case swimSuitGraphite
    case swimSuitCobalt
    case swimCapBlack
    case swimCapWhite
    case swimGogglesSmoke

    case barefoot

    var id: String { rawValue }
}
