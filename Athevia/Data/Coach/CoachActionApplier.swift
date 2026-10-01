import Foundation
import SwiftData

enum CoachActionError: Error, LocalizedError, Equatable {
    case confirmationRequired
    case previewAlreadyApplied
    case stalePreview
    case athleteScopeMismatch
    case planMissing
    case actionNoLongerMatchesPreview
    case undoUnavailable
    case undoWouldOverwriteNewerChanges

    var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            "Apply must be explicitly confirmed."
        case .previewAlreadyApplied:
            "This plan change has already been applied."
        case .stalePreview:
            "Training data or the plan changed after this preview. Review a fresh preview before applying."
        case .athleteScopeMismatch:
            "This preview belongs to a different athlete profile."
        case .planMissing:
            "The plan used for this preview is no longer available."
        case .actionNoLongerMatchesPreview:
            "The deterministic validation result changed. Review a fresh preview before applying."
        case .undoUnavailable:
            "There is no eligible coach change to undo."
        case .undoWouldOverwriteNewerChanges:
            "The plan changed after this coach action, so undo would overwrite newer work."
        }
    }
}

struct CoachPlanUndoSnapshot: Codable, Equatable {
    let generationReason: String
    let generationReasonCode: PlanGenerationReason?
    let parameters: TrainingParameters
    let futureGeneratedWorkouts: [CoachWorkoutSnapshot]
}

struct CoachAppliedActionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let preview: CoachPlanChangePreview
    let appliedAt: Date
    let postApplyPlanVersion: String
    let undoSnapshot: CoachPlanUndoSnapshot?
    var undoneAt: Date?

    init(
        preview: CoachPlanChangePreview,
        appliedAt: Date,
        postApplyPlanVersion: String,
        undoSnapshot: CoachPlanUndoSnapshot?
    ) {
        id = preview.id
        self.preview = preview
        self.appliedAt = appliedAt
        self.postApplyPlanVersion = postApplyPlanVersion
        self.undoSnapshot = undoSnapshot
        undoneAt = nil
    }
}

/// Local, athlete-scoped audit journal. It is intentionally bounded and is not
/// emitted to analytics or ordinary logs.
struct CoachActionJournal {
    private let defaults: UserDefaults
    private let key: String
    private let maximumRecords: Int

    init(
        athleteScopeID: String,
        defaults: UserDefaults = .standard,
        maximumRecords: Int = 20
    ) {
        self.defaults = defaults
        key = "athevia.coach-actions.v1.\(athleteScopeID)"
        self.maximumRecords = maximumRecords
    }

    func records() -> [CoachAppliedActionRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let records = try? decoder.decode(
            [CoachAppliedActionRecord].self,
            from: data
        ) else {
            return []
        }
        return records.sorted { $0.appliedAt < $1.appliedAt }
    }

    func hasApplied(_ previewID: UUID) -> Bool {
        records().contains { $0.preview.id == previewID }
    }

    func record(_ record: CoachAppliedActionRecord) {
        var values = records()
        values.removeAll { $0.id == record.id }
        values.append(record)
        if values.count > maximumRecords {
            values.removeFirst(values.count - maximumRecords)
        }
        save(values)
    }

    func latestUndoable(planID: UUID) -> CoachAppliedActionRecord? {
        records().reversed().first {
            $0.preview.planID == planID
                && $0.undoSnapshot != nil
                && $0.undoneAt == nil
        }
    }

    func markUndone(_ id: UUID, at date: Date) {
        var values = records()
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index].undoneAt = date
        save(values)
    }

    private func save(_ values: [CoachAppliedActionRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(values) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
struct CoachActionApplier {
    var context: ModelContext
    var calendar: Calendar = .current
    var reconcileWatch: (WeeklyPlan?, Date) async -> Void = { plan, now in
        _ = WatchAppPlanSync.sync(plan)
        _ = await WatchScheduleSync.sync(plan, now: now)
    }

    @discardableResult
    func apply(
        _ preview: CoachPlanChangePreview,
        confirmed: Bool,
        profile: AthleteProfile,
        plan: WeeklyPlan,
        currentContext: AthleteContextSnapshot,
        asOf now: Date = .now
    ) async throws -> CoachAppliedActionRecord {
        guard confirmed else { throw CoachActionError.confirmationRequired }
        guard preview.athleteScopeID == profile.id.uuidString,
              currentContext.athleteScopeID == profile.id.uuidString else {
            throw CoachActionError.athleteScopeMismatch
        }
        guard preview.planID == plan.id else { throw CoachActionError.planMissing }

        let journal = CoachActionJournal(athleteScopeID: preview.athleteScopeID)
        guard !journal.hasApplied(preview.id) else {
            throw CoachActionError.previewAlreadyApplied
        }
        guard preview.basePlanVersion == CoachPlanVersion.fingerprint(plan),
              preview.contextVersion == currentContext.version else {
            throw CoachActionError.stalePreview
        }

        let undoSnapshot = undoSnapshotIfEligible(
            for: preview.action,
            plan: plan,
            asOf: now
        )

        var store = PlanStore(context: context)
        store.reshaper.calendar = calendar

        switch preview.action {
        case .replaceWorkout(let workoutID, let replacement, let reason):
            guard let workout = plan.workouts.first(where: { $0.id == workoutID }) else {
                throw CoachActionError.actionNoLongerMatchesPreview
            }
            try store.replaceMutableWorkoutPrescription(
                workout,
                in: plan,
                with: replacement,
                generationReason: reason,
                asOf: now
            )

        case .reshapeWeek(let temporarySchedule, let expectedChanges):
            var validator = PlanReshaper()
            validator.calendar = calendar
            guard let setup = profile.setup else {
                throw CoachActionError.actionNoLongerMatchesPreview
            }
            let outcome = validator.reshape(
                plan,
                schedule: temporarySchedule,
                preferences: setup.preferences,
                asOf: now
            )
            let actual = outcome.changes.map(CoachReshapeExpectation.init)
            guard actual == expectedChanges else {
                throw CoachActionError.actionNoLongerMatchesPreview
            }
            _ = try store.reshapeWeek(
                plan,
                using: temporarySchedule,
                reason: .availabilityChanged,
                asOf: now
            )

        case .changeObjective(let before, let after):
            guard var setup = profile.setup,
                  setup.objective == before else {
                throw CoachActionError.actionNoLongerMatchesPreview
            }
            let oldSetup = setup
            let planRollback = makePlanSnapshot(plan: plan, asOf: now)
            setup.objective = after
            profile.setup = setup

            do {
                try context.save()
                _ = try store.reassess(
                    plan,
                    poolLengthMeters: profile.poolLengthMeters,
                    asOf: now
                )
            } catch {
                profile.setup = oldSetup
                restore(planRollback, to: plan, asOf: now)
                try? context.save()
                throw error
            }
        }

        let postVersion = CoachPlanVersion.fingerprint(plan)
        var appliedPreview = preview
        appliedPreview.confirmationState = .applied
        let record = CoachAppliedActionRecord(
            preview: appliedPreview,
            appliedAt: now,
            postApplyPlanVersion: postVersion,
            undoSnapshot: undoSnapshot
        )
        journal.record(record)

        await reconcileWatch(plan, now)
        return record
    }

    @discardableResult
    func undoLatestEligibleChange(
        profile: AthleteProfile,
        plan: WeeklyPlan,
        asOf now: Date = .now
    ) async throws -> CoachAppliedActionRecord {
        let journal = CoachActionJournal(athleteScopeID: profile.id.uuidString)
        guard var record = journal.latestUndoable(planID: plan.id),
              let snapshot = record.undoSnapshot else {
            throw CoachActionError.undoUnavailable
        }

        guard CoachPlanVersion.fingerprint(plan) == record.postApplyPlanVersion else {
            throw CoachActionError.undoWouldOverwriteNewerChanges
        }

        // If anything that was eligible immediately after Apply has since gained
        // completion/import/recovery evidence, the plan fingerprint above will
        // differ and this path is blocked before any deletion occurs.
        restore(snapshot, to: plan, asOf: now)
        try context.save()

        record.undoneAt = now
        journal.markUndone(record.id, at: now)
        await reconcileWatch(plan, now)
        return record
    }

    private func undoSnapshotIfEligible(
        for action: CoachPlanAction,
        plan: WeeklyPlan,
        asOf now: Date
    ) -> CoachPlanUndoSnapshot? {
        switch action {
        case .changeObjective:
            // Objective changes may cascade into journey state and profile
            // semantics. They require a new explicit change rather than an
            // opaque one-tap profile rollback.
            return nil
        case .replaceWorkout, .reshapeWeek:
            break
        }

        return makePlanSnapshot(plan: plan, asOf: now)
    }

    private func makePlanSnapshot(
        plan: WeeklyPlan,
        asOf now: Date
    ) -> CoachPlanUndoSnapshot {
        var reshaper = PlanReshaper()
        reshaper.calendar = calendar
        let boundary = calendar.startOfDay(for: now)
        let snapshots = plan.orderedWorkouts
            .filter {
                calendar.startOfDay(for: $0.date) >= boundary
                    && reshaper.isUnrecorded($0)
                    && $0.origin == .generated
            }
            .map(CoachWorkoutSnapshot.init)

        return CoachPlanUndoSnapshot(
            generationReason: plan.generationReason,
            generationReasonCode: plan.generationReasonCode,
            parameters: plan.parameters,
            futureGeneratedWorkouts: snapshots
        )
    }

    private func restore(
        _ snapshot: CoachPlanUndoSnapshot,
        to plan: WeeklyPlan,
        asOf now: Date
    ) {
        var reshaper = PlanReshaper()
        reshaper.calendar = calendar
        let boundary = calendar.startOfDay(for: now)
        let currentMutable = plan.orderedWorkouts.filter {
            calendar.startOfDay(for: $0.date) >= boundary
                && reshaper.isUnrecorded($0)
                && $0.origin == .generated
        }

        for workout in currentMutable {
            plan.workouts.removeAll { $0.id == workout.id }
            context.delete(workout)
        }

        for stored in snapshot.futureGeneratedWorkouts {
            let workout = stored.makeWorkout()
            plan.workouts.append(workout)
            context.insert(workout)
        }
        plan.parameters = snapshot.parameters
        plan.generationReason = snapshot.generationReason
        plan.generationReasonCode = snapshot.generationReasonCode
    }
}
