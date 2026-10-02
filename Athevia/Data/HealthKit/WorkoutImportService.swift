import Foundation
import SwiftData

/// Source-neutral workout ingestion.
///
/// Providers normalize their activities into ImportedWorkout. From that point
/// onward Athevia owns one path for historical visibility, plan matching,
/// persistence, source aliases and duplicate protection.
/// Coordinates an explicit sync across every connected workout source.
///
/// The caller supplies whichever providers are connected. Each provider uses
/// the exact same ingestion rules, and later providers see summaries inserted
/// by earlier providers so cross-source aliases can collapse duplicates.
@MainActor
struct WorkoutImportCoordinator {
    let context: ModelContext
    var calendar: Calendar = .current
    var importCutoff: Date? = TrainingResetBoundary.latest

    func syncAll(
        providers: [any WorkoutImportProviding],
        plans: [WeeklyPlan]
    ) async throws -> WorkoutImportService.Outcome {
        var combined = WorkoutImportService.Outcome()

        for provider in providers {
            var service = WorkoutImportService(
                context: context,
                provider: provider
            )
            service.calendar = calendar
            service.importCutoff = importCutoff

            combined.merge(
                try await service.syncAllRelevantWorkouts(
                    plans: plans
                )
            )
        }

        return combined
    }
}

@MainActor
struct WorkoutImportService {
    let context: ModelContext
    let provider: any WorkoutImportProviding
    var matcher: WorkoutMatcher = WorkoutMatcher()
    var calendar: Calendar = .current

    /// Activities before the most recent explicit Start Over must not be
    /// attached to a newly generated plan. Historical visibility intentionally
    /// ignores this cutoff.
    var importCutoff: Date? = TrainingResetBoundary.latest

    struct Outcome: Equatable, Sendable {
        var matched: Int = 0
        var alreadyKnown: Int = 0
        var unrecognised: Int = 0

        var foundSomething: Bool {
            matched > 0 || unrecognised > 0
        }

        mutating func merge(_ other: Outcome) {
            matched += other.matched
            alreadyKnown += other.alreadyKnown
            unrecognised += other.unrecognised
        }
    }

    private struct ClassifiedActivities {
        var fresh: [ImportedWorkout] = []
        var known: [(ImportedWorkout, ImportedWorkoutSummary)] = []
        var changedExisting = false
    }

    /// Boundary between pre-Athevia history and workouts eligible to match the
    /// first generated plan.
    ///
    /// WeeklyPlan.startDate is always Monday. Onboarding can happen later in
    /// that week, so using startDate alone creates a blind spot for workouts
    /// completed between Monday and the actual plan-generation time.
    static func historicalBoundary(
        for plans: [WeeklyPlan],
        fallback: Date = .now
    ) -> Date {
        guard let first = plans.min(by: {
            $0.startDate < $1.startDate
        }) else {
            return fallback
        }

        guard first.generationReasonCode == .initialAssessment else {
            return first.startDate
        }

        return max(first.startDate, first.generatedAt)
    }

    /// One entry point for an explicit "sync now" action, regardless of source.
    ///
    /// Callers do not decide date ownership. The service imports history before
    /// Athevia took ownership, then processes every generated plan window.
    @discardableResult
    func syncAllRelevantWorkouts(
        plans: [WeeklyPlan]
    ) async throws -> Outcome {
        guard !PhoneWorkoutExecutionState.isActive else {
            return Outcome()
        }

        let ordered = plans.sorted {
            $0.startDate < $1.startDate
        }
        guard !ordered.isEmpty else {
            return Outcome()
        }

        var combined = Outcome()
        let boundary = Self.historicalBoundary(
            for: ordered
        )

        combined.merge(
            try await syncHistoricalTrainingHistory(
                before: boundary
            )
        )

        for plan in ordered {
            combined.merge(
                try await importWorkouts(for: plan)
            )
        }

        return combined
    }

    @discardableResult
    func importWorkouts(
        for plan: WeeklyPlan
    ) async throws -> Outcome {
        // A workout can start on the final day and finish after midnight.
        let end = calendar.date(
            byAdding: .day,
            value: 1,
            to: plan.endDate
        ) ?? plan.endDate

        let activities = try await provider.workouts(
            from: plan.startDate,
            to: end
        )

        // The provider fetch can outlive the tap that starts a phone workout.
        guard !PhoneWorkoutExecutionState.isActive else {
            return Outcome()
        }

        let repairedMisdatedImport =
            reconcileMisdatedImportedWorkouts(in: plan)

        let effectiveCutoff: Date? = {
            let planCutoff =
                plan.generationReasonCode == .initialAssessment
                    ? plan.generatedAt
                    : nil

            return [importCutoff, planCutoff]
                .compactMap { $0 }
                .max()
        }()

        let eligible = activities.filter { activity in
            guard let effectiveCutoff else {
                return true
            }
            return activity.startDate >= effectiveCutoff
        }

        let stored = try context.fetch(
            FetchDescriptor<ImportedWorkoutSummary>()
        )
        let classified = classify(
            eligible,
            against: stored
        )

        let result = matcher.match(
            planned: plan.orderedWorkouts,
            with: classified.fresh
        )

        for match in result.matches {
            let summary = ImportedWorkoutSummary(
                match.imported
            )
            context.insert(summary)
            match.planned.attach(summary)
        }

        for activity in result.unmatchedImported {
            let recorded = importedWorkout(
                for: activity,
                status: .completed
            )
            let summary = ImportedWorkoutSummary(
                activity
            )

            context.insert(recorded)
            context.insert(summary)
            recorded.attach(summary)
            plan.workouts.append(recorded)
        }

        resolveEventCompletion(
            from: classified.fresh
        )

        if !classified.fresh.isEmpty
            || repairedMisdatedImport
            || classified.changedExisting {
            try context.save()
        }

        return Outcome(
            matched: result.matches.count,
            alreadyKnown: classified.known.count,
            unrecognised:
                result.unmatchedImported.count
        )
    }

    /// Imports training that predates Athevia's ownership as standalone
    /// completed workouts. These remain visible history but are never attached
    /// to a newer prescription.
    ///
    /// This intentionally ignores Start Over: resetting local plan data must
    /// not erase the athlete's real history from connected sources.
    @discardableResult
    func syncHistoricalTrainingHistory(
        before boundary: Date
    ) async throws -> Outcome {
        guard !PhoneWorkoutExecutionState.isActive else {
            return Outcome()
        }

        let activities = try await provider.workouts(
            from: .distantPast,
            to: boundary
        )
        .filter { activity in
            activity.startDate < boundary
                && activity.discipline.isTrainingSession
        }

        let stored = try context.fetch(
            FetchDescriptor<ImportedWorkoutSummary>()
        )
        let classified = classify(
            activities,
            against: stored
        )

        var importedCount = 0

        // Older builds could persist evidence without a visible workout row.
        // Rehydrate it rather than silently hiding a valid activity.
        for (_, summary) in classified.known
        where summary.workout == nil {
            let workout = importedWorkout(
                discipline: summary.discipline,
                sport: summary.sport,
                date: summary.startDate,
                status: .completed
            )
            context.insert(workout)
            workout.attach(summary)
            importedCount += 1
        }

        for activity in classified.fresh {
            let workout = importedWorkout(
                for: activity,
                status: .completed
            )
            let summary = ImportedWorkoutSummary(
                activity
            )

            context.insert(workout)
            context.insert(summary)
            workout.attach(summary)
            importedCount += 1
        }

        if importedCount > 0
            || classified.changedExisting {
            try context.save()
        }

        return Outcome(
            matched: 0,
            alreadyKnown: classified.known.count,
            unrecognised: importedCount
        )
    }

    /// Splits incoming activities into new physical workouts and workouts that
    /// Athevia already knows. Recognition has two layers:
    ///
    /// 1. exact provider identity / previously recorded source alias;
    /// 2. conservative physical equivalence for the same activity arriving from
    ///    another provider (for example Strava directly and via Apple Health).
    private func classify(
        _ activities: [ImportedWorkout],
        against summaries: [ImportedWorkoutSummary]
    ) -> ClassifiedActivities {
        var result = ClassifiedActivities()

        for activity in activities {
            if let summary = existingSummary(
                for: activity,
                in: summaries
            ) {
                result.known.append(
                    (activity, summary)
                )
                result.changedExisting =
                    refresh(
                        summary,
                        from: activity
                    ) || result.changedExisting
            } else if !result.fresh.contains(
                where: {
                    samePhysicalWorkout(
                        $0,
                        activity
                    )
                }
            ) {
                result.fresh.append(activity)
            }
        }

        return result
    }

    private func existingSummary(
        for activity: ImportedWorkout,
        in summaries: [ImportedWorkoutSummary]
    ) -> ImportedWorkoutSummary? {
        if let exact = summaries.first(
            where: {
                $0.importID == activity.importID
            }
        ) {
            return exact
        }

        if let alias = summaries.first(
            where: {
                $0.importAliases.contains(
                    activity.identity.alias
                )
            }
        ) {
            return alias
        }

        return summaries.first(
            where: {
                samePhysicalWorkout(
                    $0,
                    activity
                )
            }
        )
    }

    /// Cross-source duplicate detection is intentionally conservative. A direct
    /// provider and Apple Health normally preserve nearly identical timestamps,
    /// duration and distance for the same physical workout.
    private func samePhysicalWorkout(
        _ summary: ImportedWorkoutSummary,
        _ activity: ImportedWorkout
    ) -> Bool {
        guard summary.discipline
                == activity.discipline else {
            return false
        }

        let startDelta = abs(
            summary.startDate.timeIntervalSince(
                activity.startDate
            )
        )
        guard startDelta <= 120 else {
            return false
        }

        let durationDelta = abs(
            summary.duration - activity.duration
        )
        let durationTolerance = max(
            120,
            max(
                summary.duration,
                activity.duration
            ) * 0.05
        )
        guard durationDelta <= durationTolerance else {
            return false
        }

        if let storedDistance = summary.distanceMeters,
           let incomingDistance = activity.distanceMeters {
            let distanceTolerance = max(
                100,
                max(
                    storedDistance,
                    incomingDistance
                ) * 0.03
            )
            guard abs(
                storedDistance - incomingDistance
            ) <= distanceTolerance else {
                return false
            }
        }

        return true
    }

    private func samePhysicalWorkout(
        _ lhs: ImportedWorkout,
        _ rhs: ImportedWorkout
    ) -> Bool {
        guard lhs.discipline == rhs.discipline else {
            return false
        }

        let startDelta = abs(
            lhs.startDate.timeIntervalSince(
                rhs.startDate
            )
        )
        guard startDelta <= 120 else {
            return false
        }

        let durationDelta = abs(
            lhs.duration - rhs.duration
        )
        let durationTolerance = max(
            120,
            max(lhs.duration, rhs.duration) * 0.05
        )
        guard durationDelta <= durationTolerance else {
            return false
        }

        if let left = lhs.distanceMeters,
           let right = rhs.distanceMeters {
            let distanceTolerance = max(
                100,
                max(left, right) * 0.03
            )
            guard abs(left - right)
                    <= distanceTolerance else {
                return false
            }
        }

        return true
    }

    /// Refreshes known evidence without throwing away richer values already
    /// captured from another source.
    @discardableResult
    private func refresh(
        _ summary: ImportedWorkoutSummary,
        from activity: ImportedWorkout
    ) -> Bool {
        summary.sport = activity.sport
        summary.startDate = activity.startDate
        summary.endDate = activity.endDate
        summary.duration = activity.duration

        if let value = activity.distanceMeters {
            summary.distanceMeters = value
        }
        if let value = activity.averageHeartRate {
            summary.averageHeartRate = value
        }
        if let value = activity.maximumHeartRate {
            summary.maximumHeartRate = value
        }
        if let value = activity.elevationAscendedMeters {
            summary.elevationAscendedMeters = value
        }
        if let value = activity.swimmingLengths {
            summary.swimmingLengths = value
        }
        if let value = activity.swimmingStrokeCount {
            summary.swimmingStrokeCount = value
        }
        if let value =
            activity.longestContinuousSwimMeters {
            summary.longestContinuousSwimMeters =
                value
        }
        if let source = activity.source {
            summary.source = source
        }

        var merged = summary.metrics
            ?? RecordedMetrics()
        mergeMetrics(
            &merged,
            incoming: activity.metrics
        )
        merged.recordImportAlias(
            activity.identity.alias
        )
        summary.metrics = merged

        if let workout = summary.workout,
           workout.origin == .imported,
           workout.title
            != importedWorkoutTitle(
                for: summary
            ) {
            workout.title = importedWorkoutTitle(
                for: summary
            )
        }

        return true
    }

    private func mergeMetrics(
        _ target: inout RecordedMetrics,
        incoming: RecordedMetrics
    ) {
        if let value = incoming.averageCadence {
            target.averageCadence = value
        }
        if let value = incoming.averageRunningSpeed {
            target.averageRunningSpeed = value
        }
        if let value = incoming.averageRunningPower {
            target.averageRunningPower = value
        }
        if let value = incoming.averageStrideLength {
            target.averageStrideLength = value
        }
        if let value =
            incoming.averageGroundContactTime {
            target.averageGroundContactTime = value
        }
        if let value =
            incoming.averageVerticalOscillation {
            target.averageVerticalOscillation = value
        }
        if let value = incoming.averageCyclingSpeed {
            target.averageCyclingSpeed = value
        }
        if let value = incoming.averageCyclingCadence {
            target.averageCyclingCadence = value
        }
        if let value = incoming.averageCyclingPower {
            target.averageCyclingPower = value
        }
        if let value =
            incoming.functionalThresholdPower {
            target.functionalThresholdPower = value
        }
        if let value =
            incoming.activeEnergyKilocalories {
            target.activeEnergyKilocalories = value
        }
        if let value = incoming.workoutEffort {
            target.workoutEffort = value
        }
        if let value =
            incoming.estimatedWorkoutEffort {
            target.estimatedWorkoutEffort = value
        }
        if !incoming.multisportSegments.isEmpty {
            target.multisportSegments =
                incoming.multisportSegments
        }
        if let value = incoming.swimEnvironment {
            target.swimEnvironment = value
        }
        if !incoming.route.isEmpty {
            target.route = incoming.route
        }

        for alias in incoming.importAliases {
            target.recordImportAlias(alias)
        }
    }

    private func importedWorkout(
        for activity: ImportedWorkout,
        status: PlannedWorkoutStatus
    ) -> PlannedWorkout {
        importedWorkout(
            discipline: activity.discipline,
            sport: activity.sport,
            date: activity.startDate,
            status: status
        )
    }

    private func importedWorkout(
        discipline: Discipline,
        sport: Sport,
        date: Date,
        status: PlannedWorkoutStatus
    ) -> PlannedWorkout {
        PlannedWorkout(
            date: calendar.startOfDay(for: date),
            discipline: discipline,
            title: discipline == .multisport
                ? "Multisport"
                : sport.displayName,
            status: status,
            origin: .imported
        )
    }

    /// Older builds trusted an Athevia Watch planned-workout ID even when the
    /// athlete actually recorded that workout on a different day.
    private func reconcileMisdatedImportedWorkouts(
        in plan: WeeklyPlan
    ) -> Bool {
        var changed = false

        for planned in plan.orderedWorkouts
        where planned.origin != .imported {
            guard planned.discipline.isTrainingSession,
                  let summary = planned.importedSummary,
                  !calendar.isDate(
                    planned.date,
                    inSameDayAs: summary.startDate
                  ) else {
                continue
            }

            let feedback = planned.feedback
            let recoveryCheckIn =
                planned.recoveryCheckIn

            planned.feedback = nil
            planned.recoveryCheckIn = nil
            planned.importedSummary = nil
            planned.status = .planned
            planned.completedAt = nil

            let recorded = importedWorkout(
                discipline: summary.discipline,
                sport: summary.sport,
                date: summary.startDate,
                status: .completed
            )
            context.insert(recorded)
            plan.workouts.append(recorded)
            recorded.attach(summary)

            if let feedback {
                recorded.feedback = feedback
            }
            if let recoveryCheckIn {
                recorded.recoveryCheckIn =
                    recoveryCheckIn
            }

            changed = true
        }

        return changed
    }

    private func importedWorkoutTitle(
        for summary: ImportedWorkoutSummary
    ) -> String {
        summary.discipline == .multisport
            ? "Multisport"
            : summary.sport.displayName
    }

    private func resolveEventCompletion(
        from activities: [ImportedWorkout]
    ) {
        guard !activities.isEmpty,
              let profile = try? context.fetch(
                FetchDescriptor<AthleteProfile>()
              ).first,
              var setup = profile.setup,
              setup.eventState.status == .upcoming,
              let event = setup.objective.event else {
            return
        }

        let evidenceMatcher =
            EventCompletionEvidenceMatcher(
                calendar: calendar
            )
        guard let evidence = activities.first(
            where: {
                evidenceMatcher.matches(
                    event: event,
                    imported: $0
                )
            }
        ) else {
            return
        }

        let source: EventCompletionEvidenceSource
        if evidence.plannedWorkoutID != nil {
            source = .atheviaWorkout
        } else if evidence.identity.providerID
                    == "appleHealth" {
            source = .healthKitImport
        } else {
            source = .importedWorkout
        }

        setup.eventState = AthleteEventState(
            status: .completed,
            resolvedAt: evidence.endDate,
            completionEvidence: source
        )
        profile.setup = setup
    }
}
