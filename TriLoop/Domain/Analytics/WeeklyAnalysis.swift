import Foundation

/// One sport's verdict for a week.
struct SportAnalysis: Equatable, Sendable, Identifiable {
    let sport: Sport
    let status: AssessmentStatus
    let plannedSessions: Int
    let completedSessions: Int
    let averageRPE: Double?
    let highestPain: Int
    let totalDurationSeconds: TimeInterval
    let totalDistanceMeters: Double
    let reasons: [AssessmentReason]
    let adjustment: TrainingAdjustment

    var id: Sport { sport }

    var completedEverySession: Bool {
        plannedSessions > 0 && completedSessions == plannedSessions
    }
}

/// The §18 week review: one verdict per sport, plus the week's headline counts.
struct WeeklyAnalysis: Equatable, Sendable {
    let weekNumber: Int
    let startDate: Date
    let endDate: Date
    let plannedSessions: Int
    let completedSessions: Int
    /// Ordered by `Sport.allCases` so the review never reshuffles between runs.
    let sports: [SportAnalysis]

    func analysis(for sport: Sport) -> SportAnalysis? {
        sports.first { $0.sport == sport }
    }

    var completedEverySession: Bool {
        plannedSessions > 0 && completedSessions == plannedSessions
    }

    /// True once every planned session has been reported on, which is the point
    /// at which generating the next week is meaningful rather than premature.
    var isReadyForNextWeek: Bool {
        completedEverySession
    }
}
