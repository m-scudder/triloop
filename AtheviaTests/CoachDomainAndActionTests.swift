import Foundation
import SwiftData
import Testing

@testable import Athevia

@Suite("Coach deterministic domain engine")
@MainActor
struct CoachDomainEngineTests {

    @Test("Explanation is grounded and never proposes a mutation")
    func explanationOnly() {
        let plan = CoachTestFixture.seedPlan()
        plan.generationReasonCode = .profileChanged
        let profile = CoachTestFixture.profile()
        let context = CoachTestFixture.context(profile: profile, plans: [plan])

        let response = CoachDomainEngine(
            calendar: CoachTestFixture.calendar
        ).respond(
            to: .explainWorkout(date: plan.startDate),
            originalRequest: "Why is this planned?",
            context: context,
            setup: profile.setup!,
            currentPlan: plan,
            plans: [plan],
            asOf: plan.startDate
        )

        #expect(response.preview == nil)
        #expect(response.message.contains(plan.workout(on: plan.startDate, calendar: CoachTestFixture.calendar)!.title))
        #expect(response.evidenceSummary.contains("Data used"))
    }

    @Test("Reported safety evidence overrides request for training load")
    func recoverySafetyOverride() throws {
        let plan = CoachTestFixture.seedPlan()
        let monday = try #require(plan.workout(on: plan.startDate, calendar: CoachTestFixture.calendar))
        monday.recordCompletion(
            with: FeedbackDraft(
                rpe: 5,
                painScore: 6,
                painLocations: [.knee],
                recoveryFeeling: .tired
            ),
            at: plan.startDate.addingTimeInterval(60 * 60)
        )

        let targetDate = CoachTestFixture.calendar.date(
            byAdding: .day,
            value: 2,
            to: plan.startDate
        )!
        let profile = CoachTestFixture.profile()
        let context = CoachTestFixture.context(
            profile: profile,
            plans: [plan],
            asOf: plan.startDate.addingTimeInterval(24 * 60 * 60)
        )
        #expect(context.capability.recoveryState == CapabilityRecoveryState.needsAttention.rawValue)

        let response = CoachDomainEngine(
            calendar: CoachTestFixture.calendar
        ).respond(
            to: .easeSession(date: targetDate, reason: .tired),
            originalRequest: "I feel tired. Make it easier.",
            context: context,
            setup: profile.setup!,
            currentPlan: plan,
            plans: [plan],
            asOf: plan.startDate.addingTimeInterval(24 * 60 * 60)
        )

        let preview = try #require(response.preview)
        let change = try #require(preview.changes.first)
        #expect(change.after?.discipline == .recovery)
        #expect(preview.reasons.contains { $0.lowercased().contains("recovery") })
    }

    @Test("Unavailable-day preview uses PlanReshaper and leaves history untouched")
    func unavailableDayPreview() throws {
        let plan = CoachTestFixture.seedPlan()
        let profile = CoachTestFixture.profile()
        let before = CoachPlanVersion.fingerprint(plan)
        let target = CoachTestFixture.calendar.date(
            byAdding: .day,
            value: 2,
            to: plan.startDate
        )!
        let context = CoachTestFixture.context(profile: profile, plans: [plan])

        let response = CoachDomainEngine(
            calendar: CoachTestFixture.calendar
        ).respond(
            to: .unavailable(date: target),
            originalRequest: "I cannot train on Wednesday.",
            context: context,
            setup: profile.setup!,
            currentPlan: plan,
            plans: [plan],
            asOf: plan.startDate
        )

        let preview = try #require(response.preview)
        if case .reshapeWeek(_, let expected) = preview.action {
            #expect(!expected.isEmpty)
        } else {
            Issue.record("Unavailable day must produce a typed reshape action.")
        }
        #expect(CoachPlanVersion.fingerprint(plan) == before)
    }

    @Test("5K planning requires a material event date before changing the goal")
    func fiveKRequiresDate() {
        let plan = CoachTestFixture.seedPlan()
        let profile = CoachTestFixture.profile()
        let context = CoachTestFixture.context(profile: profile, plans: [plan])

        let response = CoachDomainEngine(
            calendar: CoachTestFixture.calendar
        ).respond(
            to: .prepareFor5K(eventDate: nil),
            originalRequest: "Help me prepare for a 5K using my recent training.",
            context: context,
            setup: profile.setup!,
            currentPlan: plan,
            plans: [plan],
            asOf: plan.startDate
        )

        #expect(response.preview == nil)
        #expect(response.message.lowercased().contains("event date"))
    }

    @Test("5K goal preview is typed and does not mutate profile before Apply")
    func fiveKPreview() throws {
        let plan = CoachTestFixture.seedPlan()
        let profile = CoachTestFixture.profile()
        let before = profile.setup!.objective
        let context = CoachTestFixture.context(profile: profile, plans: [plan])
        let eventDate = CoachTestFixture.calendar.date(
            byAdding: .day,
            value: 28,
            to: plan.startDate
        )!

        let response = CoachDomainEngine(
            calendar: CoachTestFixture.calendar
        ).respond(
            to: .prepareFor5K(eventDate: eventDate),
            originalRequest: "Help me prepare for a 5K on 2026-10-26.",
            context: context,
            setup: profile.setup!,
            currentPlan: plan,
            plans: [plan],
            asOf: plan.startDate
        )

        let preview = try #require(response.preview)
        if case .changeObjective(let original, let proposed) = preview.action {
            #expect(original == before)
            #expect(proposed.kind == .event)
            #expect(proposed.event?.distance?.kind == .run5K)
            #expect(proposed.event?.eventDate == eventDate)
        } else {
            Issue.record("5K request should produce a typed objective change.")
        }
        #expect(profile.setup!.objective == before)
    }
}

@Suite("Coach confirmed mutations")
@MainActor
struct CoachActionApplierTests {

    private func containerWithCurrentWeek() throws -> (
        ModelContainer,
        AthleteProfile,
        WeeklyPlan
    ) {
        let container = try AtheviaModelContainer.make(inMemory: true)
        let profile = CoachTestFixture.profile()
        let plan = CoachTestFixture.seedPlan()
        container.mainContext.insert(profile)
        container.mainContext.insert(plan)
        try container.mainContext.save()
        return (container, profile, plan)
    }

    private func limitPreview(
        profile: AthleteProfile,
        plan: WeeklyPlan,
        minutes: Int = 30
    ) throws -> (
        AthleteContextSnapshot,
        CoachPlanChangePreview,
        PlannedWorkout
    ) {
        let target = try #require(
            plan.trainingSessions.first {
                $0.discipline == .cycling
                    && $0.date >= plan.startDate
            }
        )
        let context = CoachTestFixture.context(
            profile: profile,
            plans: [plan],
            asOf: plan.startDate
        )
        let response = CoachDomainEngine(
            calendar: CoachTestFixture.calendar
        ).respond(
            to: .limitSession(date: target.date, maxMinutes: minutes),
            originalRequest: "I only have \(minutes) minutes.",
            context: context,
            setup: profile.setup!,
            currentPlan: plan,
            plans: [plan],
            asOf: plan.startDate
        )
        return (
            context,
            try #require(response.preview),
            target
        )
    }

    @Test("Preview and cancellation path do not mutate the plan")
    func previewDoesNotMutate() throws {
        let (_, profile, plan) = try containerWithCurrentWeek()
        let before = CoachPlanVersion.fingerprint(plan)
        _ = try limitPreview(profile: profile, plan: plan)
        #expect(CoachPlanVersion.fingerprint(plan) == before)
    }

    @Test("Explicit confirmation is mandatory")
    func confirmationRequired() async throws {
        let (container, profile, plan) = try containerWithCurrentWeek()
        let (context, preview, _) = try limitPreview(
            profile: profile,
            plan: plan
        )
        var applier = CoachActionApplier(context: container.mainContext)
        applier.calendar = CoachTestFixture.calendar
        applier.reconcileWatch = { _, _ in }

        do {
            _ = try await applier.apply(
                preview,
                confirmed: false,
                profile: profile,
                plan: plan,
                currentContext: context,
                asOf: plan.startDate
            )
            Issue.record("A plan mutation occurred without confirmation.")
        } catch let error as CoachActionError {
            #expect(error == .confirmationRequired)
        }
    }

    @Test("Apply is idempotent, preserves completed history and reconciles Watch")
    func applyIsSafeAndIdempotent() async throws {
        let (container, profile, plan) = try containerWithCurrentWeek()
        let completed = try #require(plan.trainingSessions.first)
        completed.recordCompletion(
            with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good),
            at: completed.date.addingTimeInterval(45 * 60)
        )
        try container.mainContext.save()

        let (context, preview, target) = try limitPreview(
            profile: profile,
            plan: plan
        )
        let completedID = completed.id
        let feedbackID = try #require(completed.feedback?.id)
        var reconciliations = 0

        var applier = CoachActionApplier(context: container.mainContext)
        applier.calendar = CoachTestFixture.calendar
        applier.reconcileWatch = { _, _ in reconciliations += 1 }

        _ = try await applier.apply(
            preview,
            confirmed: true,
            profile: profile,
            plan: plan,
            currentContext: context,
            asOf: plan.startDate
        )

        #expect(reconciliations == 1)
        #expect(target.estimatedDurationSeconds! <= TimeInterval(20 * 60))
        let preserved = try #require(plan.workouts.first { $0.id == completedID })
        #expect(preserved.isCompleted)
        #expect(preserved.feedback?.id == feedbackID)

        do {
            _ = try await applier.apply(
                preview,
                confirmed: true,
                profile: profile,
                plan: plan,
                currentContext: context,
                asOf: plan.startDate
            )
            Issue.record("Repeated Apply should be rejected.")
        } catch let error as CoachActionError {
            #expect(error == .previewAlreadyApplied)
        }
        #expect(reconciliations == 1)
    }

    @Test("Changed plan makes preview stale before mutation")
    func stalePreviewRejected() async throws {
        let (container, profile, plan) = try containerWithCurrentWeek()
        let (context, preview, target) = try limitPreview(
            profile: profile,
            plan: plan
        )
        let originalDuration = target.estimatedDurationSeconds

        plan.generationReason = "A newer edit happened"
        try container.mainContext.save()

        var applier = CoachActionApplier(context: container.mainContext)
        applier.calendar = CoachTestFixture.calendar
        applier.reconcileWatch = { _, _ in }

        do {
            _ = try await applier.apply(
                preview,
                confirmed: true,
                profile: profile,
                plan: plan,
                currentContext: context,
                asOf: plan.startDate
            )
            Issue.record("Stale preview should not apply.")
        } catch let error as CoachActionError {
            #expect(error == .stalePreview)
        }
        #expect(target.estimatedDurationSeconds == originalDuration)
    }

    @Test("Eligible future-plan change can be safely undone")
    func safeUndo() async throws {
        let (container, profile, plan) = try containerWithCurrentWeek()
        let original = CoachPlanVersion.fingerprint(plan)
        let (context, preview, _) = try limitPreview(
            profile: profile,
            plan: plan
        )
        var reconciliations = 0
        var applier = CoachActionApplier(context: container.mainContext)
        applier.calendar = CoachTestFixture.calendar
        applier.reconcileWatch = { _, _ in reconciliations += 1 }

        _ = try await applier.apply(
            preview,
            confirmed: true,
            profile: profile,
            plan: plan,
            currentContext: context,
            asOf: plan.startDate
        )
        #expect(CoachPlanVersion.fingerprint(plan) != original)

        _ = try await applier.undoLatestEligibleChange(
            profile: profile,
            plan: plan,
            asOf: plan.startDate
        )

        #expect(CoachPlanVersion.fingerprint(plan) == original)
        #expect(reconciliations == 2)
    }

    @Test("Undo refuses to overwrite a newer edit")
    func undoDoesNotOverwriteNewerChanges() async throws {
        let (container, profile, plan) = try containerWithCurrentWeek()
        let (context, preview, _) = try limitPreview(
            profile: profile,
            plan: plan
        )
        var applier = CoachActionApplier(context: container.mainContext)
        applier.calendar = CoachTestFixture.calendar
        applier.reconcileWatch = { _, _ in }

        _ = try await applier.apply(
            preview,
            confirmed: true,
            profile: profile,
            plan: plan,
            currentContext: context,
            asOf: plan.startDate
        )
        plan.generationReason = "Subsequent manual edit"
        try container.mainContext.save()

        do {
            _ = try await applier.undoLatestEligibleChange(
                profile: profile,
                plan: plan,
                asOf: plan.startDate
            )
            Issue.record("Undo should not overwrite a newer plan change.")
        } catch let error as CoachActionError {
            #expect(error == .undoWouldOverwriteNewerChanges)
        }
    }
}
