import Foundation
import SwiftData

enum SorenessLevel: String, Codable, CaseIterable, Sendable {
    case none
    case mild
    case moderate
    case significant

    var displayName: String {
        switch self {
        case .none: "None"
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .significant: "Significant"
        }
    }

    var severity: Int {
        switch self {
        case .none: 0
        case .mild: 1
        case .moderate: 2
        case .significant: 3
        }
    }
}

enum EnergyLevel: String, Codable, CaseIterable, Sendable {
    case good
    case normal
    case low

    var displayName: String {
        switch self {
        case .good: "Good"
        case .normal: "Normal"
        case .low: "Low"
        }
    }

    /// Ascending cost, so `low` compares as worse than `good` regardless of the
    /// declaration order.
    var severity: Int {
        switch self {
        case .good: 0
        case .normal: 1
        case .low: 2
        }
    }
}

/// §8's lightweight next-day check.
///
/// Kept separate from `WorkoutFeedback` because it is answered a day later and
/// may be skipped entirely: how a session felt and how it left you are two
/// different observations.
@Model
final class RecoveryCheckIn {
    var id: UUID
    /// The day being reported on, normalized to the start of day.
    var date: Date
    var painScore: Int
    var soreness: SorenessLevel
    var energy: EnergyLevel
    var symptoms: [WarningSymptom]
    var createdAt: Date

    var workout: PlannedWorkout?

    init(
        id: UUID = UUID(),
        date: Date,
        painScore: Int = 0,
        soreness: SorenessLevel = .none,
        energy: EnergyLevel = .normal,
        symptoms: [WarningSymptom] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.painScore = min(max(painScore, PainScale.minimum), PainScale.maximum)
        self.soreness = soreness
        self.energy = energy
        self.symptoms = symptoms
        self.createdAt = createdAt
    }
}
