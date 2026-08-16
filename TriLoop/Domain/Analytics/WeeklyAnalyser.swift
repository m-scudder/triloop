import Foundation

/// Turns a finished week into one verdict per sport.
///
/// One deliberate simplification while completion is entered by hand: a session
/// marked complete counts as 100% completed. Phase 5 supplies real ratios from
/// HealthKit.
struct WeeklyAnalyser: Sendable {
    var engine: TrainingEngine = TrainingEngine()

    func analyse(_ plan: WeeklyPlan) -> WeeklyAnalysis {
        let sessions = plan.trainingSessions
        let completed = sessions.filter(\.hasReport)

        let sports: [SportAnalysis] = Sport.allCases.compactMap { sport in
            let planned = sessions.filter { $0.discipline.sport == sport }
            guard !planned.isEmpty else { return nil }
            return analyse(sport: sport, planned: planned, parameters: plan.parameters)
        }

        return WeeklyAnalysis(
            weekNumber: plan.weekNumber,
            startDate: plan.startDate,
            endDate: plan.endDate,
            plannedSessions: sessions.count,
            completedSessions: completed.count,
            sports: sports
        )
    }

    private func analyse(
        sport: Sport,
        planned: [PlannedWorkout],
        parameters: TrainingParameters
    ) -> SportAnalysis {
        let completed = planned.filter(\.hasReport)
        let reports = completed.compactMap(\.feedback)

        let assessments: [WorkoutAssessment] = completed.compactMap { workout in
            guard let report = workout.feedback else { return nil }
            return engine.evaluate(
                result: WorkoutResult(
                    sport: sport,
                    completion: 1,
                    durationSeconds: workout.estimatedDurationSeconds,
                    distanceMeters: workout.estimatedDistanceMeters,
                    prescribedRestSeconds: sport == .swimming ? parameters.swimRestSeconds : nil
                ),
                feedback: FeedbackSummary(report)
            )
        }

        // The most cautious session governs the week: a single painful run is
        // not cancelled out by an easy one.
        let governing = assessments.max { $0.status.caution < $1.status.caution }
        var status = governing?.status ?? .maintain
        var adjustment = governing?.adjustment ?? .hold
        var reasons = governing?.reasons ?? []

        let missed = planned.count - completed.count
        if missed > 0 {
            reasons.append(.sessionsMissed(count: missed))
            // Progressing off a week that was not finished would compound the gap.
            if status == .progress {
                status = .maintain
                adjustment = .hold
            }
        }

        let rpeScores = reports.map(\.rpe)

        return SportAnalysis(
            sport: sport,
            status: status,
            plannedSessions: planned.count,
            completedSessions: completed.count,
            averageRPE: rpeScores.isEmpty ? nil : Double(rpeScores.reduce(0, +)) / Double(rpeScores.count),
            highestPain: reports.map(\.painScore).max() ?? 0,
            totalDurationSeconds: completed.compactMap(\.estimatedDurationSeconds).reduce(0, +),
            totalDistanceMeters: completed.compactMap(\.estimatedDistanceMeters).reduce(0, +),
            reasons: reasons,
            adjustment: adjustment
        )
    }
}

extension PlannedWorkout {
    /// Completed *and* reported on. A session without feedback cannot be assessed.
    var hasReport: Bool {
        isCompleted && feedback != nil
    }
}
