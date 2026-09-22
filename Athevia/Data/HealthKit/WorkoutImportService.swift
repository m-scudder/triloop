import Foundation
import SwiftData

/// Pulls completed activities from a health provider and attaches them to the
/// week's planned sessions.
///
/// Idempotent: activities already stored are skipped by `healthKitUUID`, so
/// importing repeatedly is safe.
@MainActor
struct WorkoutImportService {
    let context: ModelContext
    let provider: any HealthDataProviding
    var matcher: WorkoutMatcher = WorkoutMatcher()
    var calendar: Calendar = .current
    /// Activities before the most recent explicit Start Over belong to the
    /// athlete's old training timeline and must not be attached to a fresh plan.
    var importCutoff: Date? = TrainingResetBoundary.latest

    struct Outcome: Equatable, Sendable {
        var matched: Int = 0
        var alreadyKnown: Int = 0
        var unrecognised: Int = 0

        var foundSomething: Bool { matched > 0 || unrecognised > 0 }
    }

    @MainActor
    @discardableResult
    func importWorkouts(for plan: WeeklyPlan) async throws -> Outcome {
        // A session can start on the last day and finish after midnight.
        let end = calendar.date(byAdding: .day, value: 1, to: plan.endDate) ?? plan.endDate
        let activities = try await provider.workouts(from: plan.startDate, to: end)

        // The fetch above can outlive the tap that starts a phone workout.
        // Re-check ownership after awaiting HealthKit so an already in-flight
        // import cannot attach a result and destroy the active player subtree.
        guard !PhoneWorkoutExecutionState.isActive else { return Outcome() }

        let effectiveCutoff: Date? = {
            let planCutoff = plan.generationReasonCode == .initialAssessment
                ? plan.generatedAt
                : nil

            return [importCutoff, planCutoff]
                .compactMap { $0 }
                .max()
        }()

        let eligible = activities.filter { activity in
            guard let effectiveCutoff else { return true }
            return activity.startDate >= effectiveCutoff
        }

        var known = Set(try context.fetch(FetchDescriptor<ImportedWorkoutSummary>()).map(\.healthKitUUID))
        let fresh = eligible.filter { known.insert($0.healthKitUUID).inserted }

        let result = matcher.match(planned: plan.orderedWorkouts, with: fresh)

        for match in result.matches {
            let summary = ImportedWorkoutSummary(match.imported)
            context.insert(summary)
            match.planned.attach(summary)
        }

        for activity in result.unmatchedImported {
            let recorded = PlannedWorkout(
                date: calendar.startOfDay(for: activity.startDate),
                discipline: activity.sport.discipline,
                title: "Recorded \(activity.sport.displayName)",
                origin: .imported
            )
            let summary = ImportedWorkoutSummary(activity)
            context.insert(recorded)
            context.insert(summary)
            recorded.attach(summary)
            plan.workouts.append(recorded)
        }

        if !fresh.isEmpty {
            try context.save()
        }

        return Outcome(
            matched: result.matches.count,
            alreadyKnown: eligible.count - fresh.count,
            unrecognised: result.unmatchedImported.count
        )
    }
}
