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

        let repairedMisdatedImport = reconcileMisdatedImportedWorkouts(in: plan)

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

        let storedSummaries = try context.fetch(FetchDescriptor<ImportedWorkoutSummary>())
        let summariesByID = Dictionary(
            uniqueKeysWithValues: storedSummaries.map { ($0.healthKitUUID, $0) }
        )
        let refreshedKnownSummary = refreshKnownSummaries(
            from: eligible,
            summariesByID: summariesByID
        )

        var known = Set(storedSummaries.map(\.healthKitUUID))
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
                discipline: activity.discipline,
                title: activity.discipline.displayName,
                origin: .imported
            )
            let summary = ImportedWorkoutSummary(activity)
            context.insert(recorded)
            context.insert(summary)
            recorded.attach(summary)
            plan.workouts.append(recorded)
        }

        resolveEventCompletion(from: fresh)

        if !fresh.isEmpty || repairedMisdatedImport || refreshedKnownSummary {
            try context.save()
        }

        return Outcome(
            matched: result.matches.count,
            alreadyKnown: eligible.count - fresh.count,
            unrecognised: result.unmatchedImported.count
        )
    }

    /// Explicitly imports historical Run/Swim/Cycle activities without
    /// matching them to a training plan. This is intentionally separate from
    /// weekly import so browsing old Apple Health history cannot mutate past or
    /// current prescriptions.
    @discardableResult
    func importHistoricalWorkouts(
        from startDate: Date,
        to endDate: Date
    ) async throws -> Outcome {
        let activities = try await provider.workouts(from: startDate, to: endDate)
            .filter {
                $0.discipline == .running
                    || $0.discipline == .swimming
                    || $0.discipline == .cycling
            }

        guard !PhoneWorkoutExecutionState.isActive else { return Outcome() }

        let storedSummaries = try context.fetch(
            FetchDescriptor<ImportedWorkoutSummary>()
        )
        let summariesByID = Dictionary(
            uniqueKeysWithValues: storedSummaries.map { ($0.healthKitUUID, $0) }
        )

        let refreshedKnownSummary = refreshKnownSummaries(
            from: activities,
            summariesByID: summariesByID
        )

        var importedCount = 0
        var alreadyKnown = 0

        for activity in activities {
            if let existing = summariesByID[activity.healthKitUUID] {
                alreadyKnown += 1

                if existing.workout == nil {
                    let workout = makeHistoricalWorkout(
                        discipline: existing.discipline,
                        date: existing.startDate
                    )
                    context.insert(workout)
                    workout.attach(existing)
                }
                continue
            }

            let workout = makeHistoricalWorkout(
                discipline: activity.discipline,
                date: activity.startDate
            )
            let summary = ImportedWorkoutSummary(activity)

            context.insert(workout)
            context.insert(summary)
            workout.attach(summary)
            importedCount += 1
        }

        if importedCount > 0 || refreshedKnownSummary {
            try context.save()
        }

        return Outcome(
            matched: 0,
            alreadyKnown: alreadyKnown,
            unrecognised: importedCount
        )
    }

    private func makeHistoricalWorkout(
        discipline: Discipline,
        date: Date
    ) -> PlannedWorkout {
        PlannedWorkout(
            date: calendar.startOfDay(for: date),
            discipline: discipline,
            title: discipline.displayName,
            status: .completed,
            origin: .imported
        )
    }

    /// Refresh normalized evidence for a HealthKit workout we already know.
    /// This keeps imports idempotent while allowing a later permission grant or
    /// a richer importer version to backfill fields such as swim strokes and
    /// active energy without creating a second activity.
    private func refreshKnownSummaries(
        from activities: [ImportedWorkout],
        summariesByID: [UUID: ImportedWorkoutSummary]
    ) -> Bool {
        var changed = false

        for activity in activities {
            guard let summary = summariesByID[activity.healthKitUUID] else { continue }

            summary.sport = activity.sport
            summary.startDate = activity.startDate
            summary.endDate = activity.endDate
            summary.duration = activity.duration
            summary.distanceMeters = activity.distanceMeters
            summary.averageHeartRate = activity.averageHeartRate
            summary.maximumHeartRate = activity.maximumHeartRate
            summary.elevationAscendedMeters = activity.elevationAscendedMeters
            summary.swimmingLengths = activity.swimmingLengths
            summary.swimmingStrokeCount = activity.swimmingStrokeCount
            summary.longestContinuousSwimMeters = activity.longestContinuousSwimMeters
            summary.metrics = activity.metrics.isEmpty ? nil : activity.metrics
            summary.source = activity.source
            changed = true
        }

        return changed
    }

    /// Older builds trusted an Athevia Watch planned-workout ID even when the
    /// athlete actually recorded that workout on a different day. Repair those
    /// rows before de-duplication so the real activity sits on its HealthKit day
    /// and the future prescription becomes available again.
    private func reconcileMisdatedImportedWorkouts(in plan: WeeklyPlan) -> Bool {
        var changed = false

        for planned in plan.orderedWorkouts where planned.origin != .imported {
            guard planned.discipline.isTrainingSession,
                  let summary = planned.importedSummary,
                  !calendar.isDate(planned.date, inSameDayAs: summary.startDate) else {
                continue
            }

            let feedback = planned.feedback
            let recoveryCheckIn = planned.recoveryCheckIn

            planned.feedback = nil
            planned.recoveryCheckIn = nil
            planned.importedSummary = nil
            planned.status = .planned
            planned.completedAt = nil

            let recorded = PlannedWorkout(
                date: calendar.startOfDay(for: summary.startDate),
                discipline: summary.discipline,
                title: summary.discipline.displayName,
                origin: .imported
            )
            context.insert(recorded)
            plan.workouts.append(recorded)
            recorded.attach(summary)

            if let feedback {
                recorded.feedback = feedback
            }
            if let recoveryCheckIn {
                recorded.recoveryCheckIn = recoveryCheckIn
            }

            changed = true
        }

        return changed
    }

    private func resolveEventCompletion(from activities: [ImportedWorkout]) {
        guard !activities.isEmpty,
              let profile = try? context.fetch(FetchDescriptor<AthleteProfile>()).first,
              var setup = profile.setup,
              setup.eventState.status == .upcoming,
              let event = setup.objective.event else {
            return
        }

        let evidenceMatcher = EventCompletionEvidenceMatcher(calendar: calendar)
        guard let evidence = activities.first(where: {
            evidenceMatcher.matches(event: event, imported: $0)
        }) else {
            return
        }

        setup.eventState = AthleteEventState(
            status: .completed,
            resolvedAt: evidence.endDate,
            completionEvidence: evidence.plannedWorkoutID == nil
                ? .healthKitImport
                : .atheviaWorkout
        )
        profile.setup = setup
    }
}
