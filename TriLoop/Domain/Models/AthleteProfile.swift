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

    init(
        id: UUID = UUID(),
        name: String,
        experienceLevel: ExperienceLevel = .beginner,
        trainingStartDate: Date,
        poolLengthMeters: Double = 25,
        usesMetricUnits: Bool = true
    ) {
        self.id = id
        self.name = name
        self.experienceLevel = experienceLevel
        self.trainingStartDate = trainingStartDate
        self.poolLengthMeters = poolLengthMeters
        self.usesMetricUnits = usesMetricUnits
    }
}
