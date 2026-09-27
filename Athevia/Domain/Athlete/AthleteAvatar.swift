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

enum AvatarGearID: String, Codable, CaseIterable, Identifiable, Sendable {
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
