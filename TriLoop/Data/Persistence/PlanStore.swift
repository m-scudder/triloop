import Foundation
import SwiftData

/// Persistence-side orchestration for weekly plans.
///
/// The analysis and generation themselves are pure; this only decides what gets
/// written to the store, so views never carry that logic.
@MainActor
struct PlanStore {
    let context: ModelContext
    var analyser: WeeklyAnalyser = WeeklyAnalyser()
    var generator: WeeklyPlanGenerator = WeeklyPlanGenerator()
    var reshaper: PlanReshaper = PlanReshaper()

    func hasWeek(after plan: WeeklyPlan) -> Bool {
        let target = plan.weekNumber + 1
        let descriptor = FetchDescriptor<WeeklyPlan>(
            predicate: #Predicate { $0.weekNumber == target }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Returns `nil` when the following week already exists, so tapping twice
    /// cannot produce two week 2s.
    @discardableResult
    func generateNextWeek(after plan: WeeklyPlan) -> WeeklyPlan? {
        guard !hasWeek(after: plan) else { return nil }

        let next = configuredGenerator().generate(after: plan, analysis: analyser.analyse(plan))
        plan.status = .completed
        context.insert(next)
        try? context.save()
        return next
    }

    /// The generator carries no athlete state of its own, so the stored setup is
    /// applied here. Without this the next week is built against every-day
    /// availability rather than the days the athlete chose.
    private func configuredGenerator() -> WeeklyPlanGenerator {
        var configured = generator
        guard let setup = (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first?.setup else {
            return configured
        }
        configured.schedule = setup.schedule
        configured.preferences = setup.preferences
        return configured
    }

    /// Advances only when every training session has a subjective report.
    /// Imported data alone is deliberately insufficient: the engine needs RPE,
    /// pain and recovery before it can safely prescribe another week.
    @discardableResult
    func generateNextWeekIfReady(after plan: WeeklyPlan) -> WeeklyPlan? {
        guard analyser.analyse(plan).isReadyForNextWeek else { return nil }
        return generateNextWeek(after: plan)
    }

    struct ShiftOutcome: Equatable, Sendable {
        var moved: Int = 0
        /// The session pushed off the end of the week, if it was a real one.
        var dropped: Discipline?
    }

    /// Rebuilds the days still ahead of the athlete against their current
    /// availability.
    ///
    /// Only unresolved future sessions move. Reported, skipped and past days are
    /// history, and the week's own record of why it changed is updated so a
    /// later explanation layer can say what happened.
    @discardableResult
    func reshapeWeek(_ plan: WeeklyPlan, asOf now: Date = .now) -> PlanReshaper.Outcome {
        guard let setup = athleteSetup() else { return PlanReshaper.Outcome() }

        let outcome = reshaper.reshape(
            plan,
            schedule: setup.schedule,
            preferences: setup.preferences,
            asOf: now
        )

        guard !outcome.isUnchanged else { return outcome }

        let calendar = reshaper.calendar

        for change in outcome.changes {
            if let existing = plan.workout(on: change.date, calendar: calendar) {
                context.delete(existing)
            }

            let replacement = WorkoutTemplates.session(
                change.discipline,
                on: change.date,
                parameters: plan.parameters
            )
            replacement.plan = plan
            context.insert(replacement)
        }

        plan.generationReasonCode = .availabilityChanged
        try? context.save()
        return outcome
    }

    private func athleteSetup() -> AthleteSetup? {
        (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first?.setup
    }

    /// Pushes everything from `date` onward forward by a day, turning the missed
    /// day into recovery.
    ///
    /// The sequence rotates rather than each session being rescheduled
    /// individually, so the spacing between sports is preserved. Whatever falls
    /// past Sunday is dropped: extending the week would shift every following
    /// week with it.
    @discardableResult
    func shiftWeekForward(
        _ plan: WeeklyPlan,
        from date: Date,
        calendar: Calendar = .current
    ) -> ShiftOutcome {
        let day = calendar.startOfDay(for: date)
        guard plan.contains(day, calendar: calendar) else { return ShiftOutcome() }

        let affected = plan.orderedWorkouts.filter { calendar.startOfDay(for: $0.date) >= day }
        guard let missed = affected.first, !missed.hasReport, !missed.isSkipped else { return ShiftOutcome() }

        var outcome = ShiftOutcome()

        // The last day has nowhere to move to.
        if let last = affected.last, calendar.isDate(last.date, inSameDayAs: plan.endDate) {
            if last.discipline.isTrainingSession {
                outcome.dropped = last.discipline
            }
            context.delete(last)
        }

        for workout in affected.dropLast().reversed() {
            guard let next = calendar.date(byAdding: .day, value: 1, to: workout.date) else { continue }
            workout.date = next
            outcome.moved += 1
        }

        let recovery = WorkoutTemplates.recoveryDay(
            on: day,
            goal: "Rescheduled day. The rest of the week has moved on by one."
        )
        recovery.plan = plan
        context.insert(recovery)

        try? context.save()
        return outcome
    }
}
