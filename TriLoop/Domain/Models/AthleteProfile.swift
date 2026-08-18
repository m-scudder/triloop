import Foundation
import SwiftData

enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
    case beginner
    case developing
    case intermediate

    var displayName: String {
        switch self {
        case .beginner: "Beginner"
        case .developing: "Developing"
        case .intermediate: "Intermediate"
        }
    }
}

@Model
final class AthleteProfile {
    var id: UUID
    var name: String
    var experienceLevel: ExperienceLevel
    var trainingStartDate: Date
    /// Needed to interpret swim lengths; 25 m is the common default.
    var poolLengthMeters: Double
    var usesMetricUnits: Bool
    /// Everything onboarding collected. `nil` for a profile created before
    /// personalisation existed, which is what triggers the upgrade flow.
    var setup: AthleteSetup?

    init(
        id: UUID = UUID(),
        name: String,
        experienceLevel: ExperienceLevel = .beginner,
        trainingStartDate: Date,
        poolLengthMeters: Double = 25,
        usesMetricUnits: Bool = true,
        setup: AthleteSetup? = nil
    ) {
        self.id = id
        self.name = name
        self.experienceLevel = experienceLevel
        self.trainingStartDate = trainingStartDate
        self.poolLengthMeters = poolLengthMeters
        self.usesMetricUnits = usesMetricUnits
        self.setup = setup
    }

    /// True once the athlete has been through setup. Deliberately not inferred
    /// from whether a plan exists: a migrated athlete has plans but no setup.
    var hasCompletedSetup: Bool { setup?.isComplete == true }
}
