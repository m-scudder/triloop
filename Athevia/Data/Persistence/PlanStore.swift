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

        let nextStart = generator.calendar.date(byAdding: .day, value: 1, to: plan.endDate)
        let next = configuredGenerator(forWeekStarting: nextStart)
            .generate(after: plan, analysis: analyser.analyse(plan))
        plan.status = .completed
        context.insert(next)
        try context.save()
        return next
    }

    /// The generator carries no athlete state of its own, so the stored setup is
    /// applied here. Without this the next week is built against every-day
    /// availability rather than the days the athlete chose.
    private func configuredGenerator(forWeekStarting weekStart: Date? = nil) -> WeeklyPlanGenerator {
        var configured = generator
        guard let profile = (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first,
              let setup = profile.setup else {
            return configured
        }
        configured.schedule = weekStart.map {
            CoachTimeOffStore(athleteScopeID: profile.id.uuidString)
                .schedule(from: setup.schedule, weekStarting: $0, calendar: configured.calendar)
        } ?? setup.schedule
        configured.preferences = setup.preferences
        let history = (try? context.fetch(
            FetchDescriptor<WeeklyPlan>(sortBy: [SortDescriptor(\.startDate)])
        )) ?? []
        let capability = AthleteCapabilityAssessmentBuilder(calendar: configured.calendar)
            .build(setup: setup, plans: history)
        configured.capability = capability
        configured.journey = TrainingJourneyPlanner(calendar: configured.calendar)
            .plan(setup: setup, capability: capability)
        configured.objective = setup.objective
        configured.openWaterConsent = setup.openWaterTrainingConsent
        configured.eventState = setup.eventState
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
        return try reshapeWeek(
            plan,
            using: setup.schedule,
            reason: .availabilityChanged,
            asOf: now
        )
    }

    /// Applies a one-week schedule override without changing the athlete's
    /// recurring profile availability. The coach uses this only after a
    /// preview has been confirmed.
    @discardableResult
    func reshapeWeek(
        _ plan: WeeklyPlan,
        using temporarySchedule: AthleteSchedule,
        reason: PlanGenerationReason = .availabilityChanged,
        asOf now: Date = .now
    ) throws -> PlanReshaper.Outcome {
        guard let setup = athleteSetup() else { return PlanReshaper.Outcome() }

        let outcome = reshaper.reshape(
            plan,
            schedule: temporarySchedule,
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
        plan.generationReasonCode = reason
        try context.save()
        return outcome
    }

    /// Replaces only the prescription of an unresolved future generated
    /// workout. Feedback, imported evidence and completed history can never
    /// reach this path because PlanReshaper.canEdit rejects them first.
    func replaceMutableWorkoutPrescription(
        _ workout: PlannedWorkout,
        in plan: WeeklyPlan,
        with snapshot: CoachWorkoutSnapshot,
        generationReason: PlanGenerationReason,
        asOf now: Date = .now
    ) throws {
        guard workout.origin == .generated,
              reshaper.canEdit(workout, in: plan, asOf: now) else {
            throw PlanReshaper.Failure.workoutIsImmutable
        }
        guard calendarSameDay(workout.date, snapshot.date, calendar: reshaper.calendar) else {
            throw PlanReshaper.Failure.dateOutsidePlan
        }
        guard snapshot.discipline == workout.discipline || snapshot.discipline == .recovery else {
            throw PlanReshaper.Failure.workoutIsImmutable
        }

        if snapshot.discipline.isTrainingSession {
            guard let setup = athleteSetup() else {
                throw PlanReshaper.Failure.missingSchedule
            }
            let candidate = snapshot.makeWorkout()
            candidate.id = workout.id
            try reshaper.validatePlacement(
                candidate,
                on: workout.date,
                in: plan,
                schedule: setup.schedule,
                asOf: now
            )
        }

        let replacement = snapshot.makeWorkout()
        let oldSteps = workout.steps
        workout.discipline = replacement.discipline
        workout.title = replacement.title
        workout.goal = replacement.goal
        workout.targetRPE = replacement.targetRPE
        workout.prescribedDurationSeconds = replacement.prescribedDurationSeconds
        workout.targetDistanceMeters = replacement.targetDistanceMeters
        workout.steps = replacement.steps
        replacement.steps = []
        for step in oldSteps { context.delete(step) }

        plan.generationReasonCode = generationReason
        try context.save()
    }

    /// Adds one Coach-proposed session after deterministic placement validation.
    /// The model never supplies the step tree directly; callers must pass a
    /// snapshot built by Athevia's prescription engine.
    func addCoachWorkout(
        _ snapshot: CoachWorkoutSnapshot,
        to plan: WeeklyPlan,
        asOf now: Date = .now
    ) throws {
        guard snapshot.discipline.isTrainingSession,
              snapshot.status == .planned else {
            throw PlanReshaper.Failure.workoutIsImmutable
        }
        guard let setup = athleteSetup() else {
            throw PlanReshaper.Failure.missingSchedule
        }

        let candidate = snapshot.makeWorkout()
        candidate.origin = .generated
        try reshaper.validatePlacement(
            candidate,
            on: snapshot.date,
            in: plan,
            schedule: setup.schedule,
            asOf: now
        )

        plan.workouts.append(candidate)
        context.insert(candidate)
        removeOccupiedRestDays(in: plan, asOf: now)
        plan.generationReason = "A workout was added after review in Athevia Coach."
        plan.generationReasonCode = .coachAdjustment
        try context.save()
    }

    private func calendarSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
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

    /// Rebuilds only unresolved future days from the athlete's *current*
    /// capability, objective, event phase, priorities and schedule.
    ///
    /// The legacy resolver parameter is retained for source compatibility with
    /// older tests/callers, but onboarding baseline is no longer allowed to
    /// reset a progressed athlete's current week.
    @discardableResult
    func reassess(
        _ plan: WeeklyPlan,
        poolLengthMeters: Double,
        resolver: any StartingParameterResolving = StartingParameterResolver(),
        asOf now: Date = .now
    ) throws -> Int {
        _ = poolLengthMeters
        _ = resolver
        guard athleteSetup() != nil else { return 0 }

        let calendar = generator.calendar
        let boundary = calendar.startOfDay(for: now)
        guard plan.status != .completed,
              calendar.startOfDay(for: plan.endDate) >= boundary else {
            return 0
        }

        let previousStart = calendar.date(
            byAdding: .day,
            value: -7,
            to: plan.startDate
        ) ?? plan.startDate
        let previousEnd = calendar.date(
            byAdding: .day,
            value: -1,
            to: plan.startDate
        ) ?? plan.startDate

        let seed = WeeklyPlan(
            weekNumber: plan.weekNumber - 1,
            startDate: previousStart,
            endDate: previousEnd,
            status: .completed,
            parameters: plan.parameters,
            workouts: []
        )
        let neutralAnalysis = WeeklyAnalysis(
            weekNumber: seed.weekNumber,
            startDate: seed.startDate,
            endDate: seed.endDate,
            plannedSessions: 0,
            completedSessions: 0,
            skippedSessions: 0,
            sports: []
        )
        let candidate = configuredGenerator(forWeekStarting: plan.startDate).generate(
            after: seed,
            analysis: neutralAnalysis
        )

        let futureExisting = plan.orderedWorkouts.filter {
            calendar.startOfDay(for: $0.date) >= boundary
        }
        let rebuildable = futureExisting.filter {
            reshaper.isUnrecorded($0) && $0.origin == .generated
        }
        let immutable = futureExisting.filter { workout in
            !rebuildable.contains(where: { $0.id == workout.id })
        }
        let immutableDays = immutable.map { calendar.startOfDay(for: $0.date) }

        for workout in rebuildable {
            plan.workouts.removeAll { $0.id == workout.id }
            context.delete(workout)
        }

        var inserted = 0
        for workout in candidate.orderedWorkouts {
            let day = calendar.startOfDay(for: workout.date)
            guard day >= boundary,
                  !immutableDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) else {
                continue
            }

            candidate.workouts.removeAll { $0.id == workout.id }
            plan.workouts.append(workout)
            context.insert(workout)
            inserted += 1
        }

        plan.parameters = candidate.parameters
        plan.generationReason = "Upcoming training rebuilt from current capability and profile."
        plan.generationReasonCode = .profileChanged
        removeOccupiedRestDays(in: plan, asOf: now)
        try context.save()
        return inserted
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
