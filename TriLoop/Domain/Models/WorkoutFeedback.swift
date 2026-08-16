import Foundation
import SwiftData

/// How recovered the athlete felt at the end of a session.
enum RecoveryFeeling: String, Codable, CaseIterable, Sendable {
    case fresh
    case good
    case okay
    case tired
    case exhausted

    var displayName: String {
        switch self {
        case .fresh: "Fresh"
        case .good: "Good"
        case .okay: "Okay"
        case .tired: "Tired"
        case .exhausted: "Exhausted"
        }
    }

    /// Ascending cost, so the training engine can compare feelings without
    /// depending on the declaration order of the enum.
    var severity: Int {
        switch self {
        case .fresh: 0
        case .good: 1
        case .okay: 2
        case .tired: 3
        case .exhausted: 4
        }
    }
}

enum PainLocation: String, Codable, CaseIterable, Sendable {
    case lowerBack
    case knee
    case shin
    case calf
    case ankle
    case hip
    case shoulder
    case other

    var displayName: String {
        switch self {
        case .lowerBack: "Lower back"
        case .knee: "Knee"
        case .shin: "Shin"
        case .calf: "Calf"
        case .ankle: "Ankle"
        case .hip: "Hip"
        case .shoulder: "Shoulder"
        case .other: "Other"
        }
    }
}

enum PainScale {
    static let minimum = 0
    static let maximum = 10

    /// Pain is reported far less precisely than effort, so only the anchors are named.
    static func label(for value: Int) -> String {
        switch value {
        case ...0: "No pain"
        case 1...2: "Barely noticeable"
        case 3...4: "Mild"
        case 5...6: "Moderate"
        case 7...8: "Severe"
        default: "Worst possible"
        }
    }
}

/// Subjective report for one completed session.
///
/// Deliberately separate from `PlannedWorkout` so a session can be marked
/// complete without feedback, and so the future next-day `RecoveryCheckIn`
/// can hang off the same workout without reshaping this type.
@Model
final class WorkoutFeedback {
    var id: UUID
    var rpe: Int
    var painScore: Int
    var painLocations: [PainLocation]
    var recoveryFeeling: RecoveryFeeling
    var notes: String
    var createdAt: Date

    var workout: PlannedWorkout?

    init(
        id: UUID = UUID(),
        rpe: Int,
        painScore: Int,
        painLocations: [PainLocation] = [],
        recoveryFeeling: RecoveryFeeling,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        let clampedPain = min(max(painScore, PainScale.minimum), PainScale.maximum)
        self.rpe = min(max(rpe, RPEScale.minimum), RPEScale.maximum)
        self.painScore = clampedPain
        self.painLocations = clampedPain == 0 ? [] : painLocations
        self.recoveryFeeling = recoveryFeeling
        self.notes = notes
        self.createdAt = createdAt
    }

    var reportedPain: Bool { painScore > 0 }
}
