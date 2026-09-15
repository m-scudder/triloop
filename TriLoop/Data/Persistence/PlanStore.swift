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
    func generateNextWeek(after plan: WeeklyPlan) throws -> WeeklyPlan? {
        guard !hasWeek(after: plan) else { return nil }

        let next = configuredGenerator().generate(after: plan, analysis: analyser.analyse(plan))
        plan.status = .completed
        context.insert(next)
        try context.save()
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
    func generateNextWeekIfReady(after plan: WeeklyPlan) throws -> WeeklyPlan? {
        guard analyser.analyse(plan).isReadyForNextWeek else { return nil }
        return try generateNextWeek(after: plan)
    }

    /// Rolls the athlete onto the week that contains today.
    ///
    /// Generation is otherwise only reachable through a full set of reports or
    /// the Plan tab's button, so a week that simply runs out leaves Today
    /// empty. A week whose last day has passed is closed and its successor
    /// built from whatever was reported, repeatedly, so a short break still
    /// ends on a current week rather than a stale one.
    ///
    /// `limit` bounds the catch-up: a long absence is better left short of
    /// today than turned into months of untouched weeks.
    @discardableResult
    func advanceToCurrentWeek(
        asOf now: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 6
    ) throws -> WeeklyPlan? {
        let today = calendar.startOfDay(for: now)
        var generated: WeeklyPlan?

        for _ in 0..<limit {
            guard let latest = latestPlan(), latest.endDate < today else { break }
            guard let next = try generateNextWeek(after: latest) else { break }
            generated = next
        }

        return generated
    }

    /// The furthest week the athlete has, which is the only one a successor can
    /// be built from.
    private func latestPlan() -> WeeklyPlan? {
        var descriptor = FetchDescriptor<WeeklyPlan>(
            sortBy: [SortDescriptor(\.weekNumber, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
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
    func reshapeWeek(_ plan: WeeklyPlan, asOf now: Date = .now) throws -> PlanReshaper.Outcome {
        guard let setup = athleteSetup() else { return PlanReshaper.Outcome() }

        let outcome = reshaper.reshape(
            plan,
            schedule: setup.schedule,
            preferences: setup.preferences,
            asOf: now
        )

        guard !outcome.isUnchanged else { return outcome }

        for change in outcome.changes {
            guard let existing = plan.workouts.first(where: { $0.id == change.workoutID }) else { continue }
            if change.skipped { existing.skip() }
            else { existing.date = change.date }
        }

        removeOccupiedRestDays(in: plan, asOf: now)
        plan.generationReasonCode = .availabilityChanged
        try context.save()
        return outcome
    }

    private func athleteSetup() -> AthleteSetup? {
        (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first?.setup
    }

    /// Rebuilds the days still ahead using different training dials, keeping
    /// each day's sport.
    ///
    /// For a reassessed baseline: the athlete says they can do more (or less)
    /// than they could, so the prescription changes while the week's shape and
    /// everything already recorded stay exactly as they are.
    @discardableResult
    func reapplyParameters(
        _ parameters: TrainingParameters,
        to plan: WeeklyPlan,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Int {
        let boundary = calendar.startOfDay(for: now)
        guard plan.status != .completed,
              calendar.startOfDay(for: plan.endDate) >= boundary else { return 0 }

        let rebuildable = plan.orderedWorkouts.filter { workout in
            calendar.startOfDay(for: workout.date) >= boundary
                && reshaper.isUnrecorded(workout)
                && workout.origin == .generated
        }

        guard !rebuildable.isEmpty else { return 0 }

        for workout in rebuildable {
            let replacement = PrescribedSessions.session(workout.discipline, on: workout.date, parameters: parameters)
            let oldSteps = workout.steps
            workout.title = replacement.title
            workout.goal = replacement.goal
            workout.targetRPE = replacement.targetRPE
            workout.prescribedDurationSeconds = replacement.prescribedDurationSeconds
            workout.targetDistanceMeters = replacement.targetDistanceMeters
            workout.steps = replacement.steps
            replacement.steps = []
            for step in oldSteps { context.delete(step) }
        }

        plan.parameters = parameters
        plan.generationReasonCode = .profileChanged
        try context.save()
        return rebuildable.count
    }

    /// Rebuilds the days ahead from the athlete's current assessment.
    ///
    /// The view asks for a reassessment; deciding what that means is the
    /// domain's job, so the resolver is called here rather than in the UI.
    @discardableResult
    func reassess(
        _ plan: WeeklyPlan,
        poolLengthMeters: Double,
        resolver: any StartingParameterResolving = StartingParameterResolver(),
        asOf now: Date = .now
    ) throws -> Int {
        guard let setup = athleteSetup() else { return 0 }

        let parameters = resolver.resolve(
            baseline: setup.baseline,
            goal: setup.goal,
            poolLengthMeters: poolLengthMeters
        )
        return try reapplyParameters(parameters, to: plan, asOf: now)
    }

    func moveWorkout(_ workout: PlannedWorkout, to date: Date, asOf now: Date = .now) throws {
        guard let plan = workout.plan else { throw PlanReshaper.Failure.workoutIsImmutable }
        try reshaper.validateWeek(plan, on: date, asOf: now)
        guard workout.discipline.isTrainingSession, reshaper.canEdit(workout, in: plan, asOf: now)
        else { throw PlanReshaper.Failure.workoutIsImmutable }
        guard let setup = athleteSetup() else { throw PlanReshaper.Failure.missingSchedule }
        try reshaper.validatePlacement(workout, on: date, in: plan, schedule: setup.schedule, asOf: now)
        workout.date = reshaper.calendar.startOfDay(for: date)
        removeOccupiedRestDays(in: plan, asOf: now)
        try context.save()
    }

    func skipWorkout(_ workout: PlannedWorkout, asOf now: Date = .now) throws {
        guard let plan = workout.plan else { throw PlanReshaper.Failure.workoutIsImmutable }
        try reshaper.validateWeek(plan, on: workout.date, asOf: now)
        guard workout.discipline.isTrainingSession, reshaper.canEdit(workout, in: plan, asOf: now)
        else { throw PlanReshaper.Failure.workoutIsImmutable }
        workout.skip()
        try context.save()
    }

    @discardableResult
    func markDayUnavailable(_ weekday: Weekday, asOf now: Date = .now) throws -> Int {
        guard let profile = try context.fetch(FetchDescriptor<AthleteProfile>()).first,
              var setup = profile.setup else { throw PlanReshaper.Failure.missingSchedule }
        setup.schedule = AthleteSchedule(days: Weekday.trainingWeek.map { day in
            var availability = setup.schedule.availability(on: day)
            if day == weekday { availability.isAvailable = false }
            return availability
        })
        profile.setup = setup
        var skipped = 0
        for plan in try context.fetch(FetchDescriptor<WeeklyPlan>()) {
            skipped += try reshapeWeek(plan, asOf: now).dropped
        }
        try context.save()
        return skipped
    }

    private func removeOccupiedRestDays(in plan: WeeklyPlan, asOf now: Date) {
        let placeholders = plan.workouts.filter { rest in
            rest.discipline == .rest && reshaper.canEdit(rest, in: plan, asOf: now)
                && plan.trainingSessions.contains {
                    !$0.isSkipped && reshaper.calendar.isDate($0.date, inSameDayAs: rest.date)
                }
        }
        for rest in placeholders {
            plan.workouts.removeAll { $0.id == rest.id }
            context.delete(rest)
        }
    }

    @discardableResult
    func shiftWeekForward(
        _ plan: WeeklyPlan,
        from date: Date,
        calendar: Calendar = .current
    ) throws -> ShiftOutcome {
        throw PlanReshaper.Failure.useSingleWorkoutMove
    }
}
