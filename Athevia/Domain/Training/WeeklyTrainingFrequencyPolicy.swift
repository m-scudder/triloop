import Foundation

/// Decides how many physiological training days a week should contain.
///
/// Availability is only the placement pool. This policy owns weekly frequency,
/// so choosing six available weekdays never silently becomes six workouts.
struct WeeklyTrainingFrequencyPolicy: Sendable {
    static let onboardingMaximum = 4
    static let engineMaximum = 5
    static let openingMaximum = 3

    func openingTarget(
        requested: Int,
        selectedSportCount: Int,
        availableDays: Int
    ) -> Int {
        let requested = min(max(requested, 2), Self.engineMaximum)
        let floor = max(1, selectedSportCount)
        return min(availableDays, max(floor, min(requested, Self.openingMaximum)))
    }

    func nextTarget(
        requested: Int,
        selectedSportCount: Int,
        availableDays: Int,
        previousPlan: WeeklyPlan,
        analysis: WeeklyAnalysis
    ) -> Int {
        let requested = min(max(requested, 2), Self.engineMaximum)
        let floor = max(1, selectedSportCount)
        let opening = openingTarget(
            requested: requested,
            selectedSportCount: selectedSportCount,
            availableDays: availableDays
        )
        let previous = max(opening, previousPlan.prescribedTrainingSessions.count)
        let cappedPrevious = min(previous, requested, availableDays)

        guard cappedPrevious < requested,
              cappedPrevious < availableDays,
              isSafeToAddDay(analysis) else {
            return max(floor, cappedPrevious)
        }

        return min(requested, availableDays, cappedPrevious + 1)
    }

    func explanation(
        requested: Int,
        actual: Int,
        previousActual: Int? = nil,
        analysis: WeeklyAnalysis? = nil
    ) -> String {
        if let previousActual, actual > previousActual {
            return "Training increased from \(previousActual) to \(actual) days after you completed the previous week well."
        }

        if requested > actual {
            if let analysis, !isSafeToAddDay(analysis) {
                return "Training stays at \(actual) days because the previous week did not yet support adding another workout."
            }
            return "Training starts at \(actual) days and builds gradually toward \(requested)."
        }

        return "\(actual) training days matches your weekly target."
    }

    private func isSafeToAddDay(_ analysis: WeeklyAnalysis) -> Bool {
        guard analysis.isReadyForNextWeek,
              analysis.completedEverySession,
              analysis.skippedSessions == 0,
              !analysis.sports.isEmpty else {
            return false
        }

        return analysis.sports.allSatisfy { sport in
            sport.status != .reduce
                && sport.status != .recoveryRequired
                && sport.highestPain <= 2
                && (sport.averageRPE ?? 0) <= 7
        }
    }
}
