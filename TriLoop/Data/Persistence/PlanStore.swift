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

    /// Rewrites the remaining days of a week to the current schedule.
    ///
    /// Needed whenever availability changes under an already-generated week —
    /// equipment arriving, a sport starting sooner than planned. Anything
    /// already reported on or deliberately skipped is left alone.
    @discardableResult
    func reshapeWeek(
        _ plan: WeeklyPlan,
        availability: SportAvailability = .athlete(),
        calendar: Calendar = .current
    ) -> Int {
        let schedule = WeeklySchedule.forWeek(
            starting: plan.startDate,
            availability: availability,
            calendar: calendar
        )
        var changed = 0

        for (offset, discipline) in schedule.disciplines.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: offset, to: plan.startDate) else { continue }
            let existing = plan.workout(on: date, calendar: calendar)

            // Anything already reported on or deliberately skipped is a decision
            // the athlete made, not a plan to be rewritten.
            if let existing, existing.hasReport || existing.isSkipped { continue }
            if let existing, existing.discipline == discipline { continue }

            if let existing {
                context.delete(existing)
            }

            let replacement = WorkoutTemplates.session(
                discipline,
                on: date,
                parameters: plan.parameters
            )
            replacement.plan = plan
            context.insert(replacement)
            changed += 1
        }

        if changed > 0 {
            try? context.save()
        }
        return changed
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
