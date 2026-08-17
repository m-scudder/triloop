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

    struct Outcome: Equatable, Sendable {
        var matched: Int = 0
        var alreadyKnown: Int = 0
        var unrecognised: Int = 0

        var foundSomething: Bool { matched > 0 }
    }

    @discardableResult
    func importWorkouts(for plan: WeeklyPlan) async throws -> Outcome {
        // A session can start on the last day and finish after midnight.
        let end = calendar.date(byAdding: .day, value: 1, to: plan.endDate) ?? plan.endDate
        let activities = try await provider.workouts(from: plan.startDate, to: end)

        let known = Set(
            (try? context.fetch(FetchDescriptor<ImportedWorkoutSummary>()))?.map(\.healthKitUUID) ?? []
        )
        let fresh = activities.filter { !known.contains($0.healthKitUUID) }

        let result = matcher.match(planned: plan.orderedWorkouts, with: fresh)

        for match in result.matches {
            let summary = ImportedWorkoutSummary(match.imported)
            context.insert(summary)
            match.planned.attach(summary)
        }

        if !result.matches.isEmpty {
            try context.save()
        }

        return Outcome(
            matched: result.matches.count,
            alreadyKnown: activities.count - fresh.count,
            unrecognised: result.unmatchedImported.count
        )
    }
}
