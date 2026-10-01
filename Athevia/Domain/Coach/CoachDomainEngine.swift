import Foundation

/// Deterministic coach domain engine. It can explain existing evidence and
/// construct candidate actions, but it never mutates SwiftData.
struct CoachDomainEngine: Sendable {
    var calendar: Calendar = .current
    var reshaper: PlanReshaper = PlanReshaper()

    func respond(
        to intent: CoachIntent,
        originalRequest: String,
        context: AthleteContextSnapshot,
        setup: AthleteSetup,
        currentPlan: WeeklyPlan,
        plans: [WeeklyPlan],
        asOf now: Date = .now
    ) -> CoachDomainResponse {
        var reshaper = reshaper
        reshaper.calendar = calendar

        switch intent {
        case .explainWorkout(let date):
            return explainWorkout(
                on: date,
                context: context,
                plan: currentPlan,
                asOf: now
            )

        case .summarizeRecentTraining(let weeks):
            return summarizeTraining(
                weeks: weeks,
                context: context,
                plans: plans,
                asOf: now
            )

        case .limitSession(let date, let minutes):
            return previewLimitedSession(
                on: date,
                minutes: minutes,
                request: originalRequest,
                intent: intent,
                context: context,
                plan: currentPlan,
                reshaper: reshaper,
                asOf: now
            )

        case .unavailable(let date):
            return previewUnavailableDay(
                date,
                request: originalRequest,
                intent: intent,
                context: context,
                setup: setup,
                plan: currentPlan,
                reshaper: reshaper,
                asOf: now
            )

        case .easeSession(let date, let reason):
            return previewEasierSession(
                on: date,
                reason: reason,
                request: originalRequest,
                intent: intent,
                context: context,
                plan: currentPlan,
                reshaper: reshaper,
                asOf: now
            )

        case .moveSession(let source, let target):
            return previewMoveSession(
                from: source,
                to: target,
                request: originalRequest,
                intent: intent,
                context: context,
                setup: setup,
                plan: currentPlan,
                reshaper: reshaper,
                asOf: now
            )

        case .skipSession(let date):
            return previewSkipSession(
                on: date,
                request: originalRequest,
                intent: intent,
                context: context,
                plan: currentPlan,
                reshaper: reshaper,
                asOf: now
            )

        case .unavailableRange(let start, let end):
            return previewUnavailableRange(
                start: start,
                end: end,
                request: originalRequest,
                intent: intent,
                context: context,
                setup: setup,
                plan: currentPlan,
                reshaper: reshaper,
                asOf: now
            )

        case .generateWorkout:
            return noChange(
                "Generated workouts must pass through the validated Coach proposal builder.",
                context: context
            )

        case .prepareFor5K(let eventDate):
            return prepareFor5K(
                eventDate: eventDate,
                request: originalRequest,
                intent: intent,
                context: context,
                setup: setup,
                plan: currentPlan,
                plans: plans,
                reshaper: reshaper,
                asOf: now
            )
        }
    }

    // MARK: - Explanations

    private func explainWorkout(
        on date: Date,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        asOf now: Date
    ) -> CoachDomainResponse {
        guard let workout = plan.workout(on: date, calendar: calendar) else {
            return CoachDomainResponse(
                message: "There is no planned session on \(dayLabel(date)).",
                evidenceSummary: evidenceSummary(context),
                preview: nil
            )
        }

        var reasons: [String] = []
        if let generationReason = plan.generationReasonCode {
            reasons.append(generationReason.displayName)
        }
        if !workout.goal.isEmpty {
            reasons.append(workout.goal)
        }

        if let sport = workout.discipline.sport,
           let capability = context.capability.sports.first(where: { $0.sport == sport }) {
            if let recent = capability.recentAverageMeters {
                reasons.append("Recent recorded \(sport.displayName.lowercased()) sessions average \(distanceLabel(recent)).")
            } else if let baseline = capability.baselineMeters {
                reasons.append("There is no stronger recent distance evidence yet, so the \(distanceLabel(baseline)) onboarding reference is still part of the context.")
            }
        }

        if context.capability.recoveryState != CapabilityRecoveryState.stable.rawValue {
            reasons.append("Recent reported recovery is \(context.capability.recoveryState); safety constraints take priority over progression.")
        }

        let detail = reasons.isEmpty
            ? "It follows the current deterministic weekly prescription."
            : reasons.joined(separator: " ")

        return CoachDomainResponse(
            message: "\(workout.title) is planned for \(dayLabel(date)). \(detail)",
            evidenceSummary: evidenceSummary(context),
            preview: nil
        )
    }

    private func summarizeTraining(
        weeks: Int,
        context: AthleteContextSnapshot,
        plans: [WeeklyPlan],
        asOf now: Date
    ) -> CoachDomainResponse {
        let clampedWeeks = min(max(weeks, 1), 8)
        let cutoff = calendar.date(byAdding: .day, value: -(clampedWeeks * 7), to: now)
            ?? .distantPast
        let selectedPlans = plans
            .filter { $0.endDate >= cutoff && $0.startDate <= now }
            .sorted { $0.startDate < $1.startDate }

        let recentHealth = context.recentHealthWorkouts.filter { $0.endDate >= cutoff }
        let planned = selectedPlans.flatMap(\.prescribedTrainingSessions)
        let completed = planned.filter(\.isCompleted)
        let skipped = planned.filter {
            $0.isSkipped || $0.isMissed(asOf: now, calendar: calendar)
        }

        var pieces: [String] = [
            "Across the last \(clampedWeeks) weeks, \(completed.count) of \(planned.count) planned training sessions were completed"
                + (skipped.isEmpty ? "." : ", with \(skipped.count) skipped or missed.")
        ]

        if let first = selectedPlans.first, let last = selectedPlans.last, first.id != last.id {
            pieces.append(contentsOf: parameterChanges(from: first.parameters, to: last.parameters))
        }

        for sport in Sport.allCases {
            let sportHealth = recentHealth.filter { $0.sport == sport }
            guard !sportHealth.isEmpty else { continue }
            let total = sportHealth.compactMap(\.distanceMeters).reduce(0, +)
            if total > 0 {
                pieces.append("\(sport.displayName): \(sportHealth.count) Apple Health session\(sportHealth.count == 1 ? "" : "s"), \(distanceLabel(total)) recorded.")
            } else {
                pieces.append("\(sport.displayName): \(sportHealth.count) Apple Health session\(sportHealth.count == 1 ? "" : "s") recorded; distance was unavailable.")
            }
        }

        if selectedPlans.isEmpty && recentHealth.isEmpty {
            pieces = ["There is not enough recent training history to compare yet."]
        }

        return CoachDomainResponse(
            message: pieces.joined(separator: " "),
            evidenceSummary: evidenceSummary(context),
            preview: nil
        )
    }

    // MARK: - Preview builders

    private func previewLimitedSession(
        on date: Date,
        minutes: Int,
        request: String,
        intent: CoachIntent,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        reshaper: PlanReshaper,
        asOf now: Date
    ) -> CoachDomainResponse {
        guard let workout = plan.workout(on: date, calendar: calendar),
              workout.discipline.isTrainingSession else {
            return noChange(
                "There is no training session to shorten on \(dayLabel(date)).",
                context: context
            )
        }
        guard reshaper.canEdit(workout, in: plan, asOf: now) else {
            return noChange(
                "That session is already completed, skipped, recorded, or in the past, so its history will not be changed.",
                context: context
            )
        }
        guard workout.discipline != .multisport else {
            return noChange(
                "A brick or multisport workout cannot be compressed safely with a single time cap. Move it to another available day instead.",
                context: context
            )
        }

        if context.capability.recoveryState == CapabilityRecoveryState.needsAttention.rawValue {
            return recoveryOverridePreview(
                workout: workout,
                request: request,
                intent: intent,
                context: context,
                plan: plan,
                reason: "Recent pain, symptoms, or recovery evidence requires recovery instead of a shortened training session.",
                asOf: now
            )
        }

        guard workout.discipline != .swimming else {
            return noChange(
                "Athevia does not convert a swim distance to a time limit without a measured pace assumption. I will not invent one; move the swim or change the day instead.",
                context: context
            )
        }

        let parameters = plan.parameters.capped(toTrainingMinutes: minutes)
        let replacement = PrescribedSessions.session(
            workout.discipline,
            on: workout.date,
            parameters: parameters,
            goal: "Fit today's training inside your \(minutes)-minute limit without increasing intensity."
        )
        guard let duration = replacement.estimatedDurationSeconds,
              duration <= TimeInterval(minutes * 60) else {
            return noChange(
                "The existing warm-up, cooldown, and minimum safe work block do not fit inside \(minutes) minutes.",
                context: context
            )
        }

        let before = CoachWorkoutSnapshot(workout)
        let after = CoachWorkoutSnapshot(replacement)
        let reason = "The session is rebuilt by Athevia's existing prescription builder with a \(minutes)-minute ceiling; progression and intensity rules are unchanged."

        return previewResponse(
            message: "I can shorten \(workout.title) on \(dayLabel(date)) to fit within \(minutes) minutes.",
            request: request,
            intent: intent,
            constraints: ["\(minutes)-minute ceiling on \(dayLabel(date))"],
            context: context,
            plan: plan,
            changes: [
                CoachWorkoutChange(
                    kind: .shortened,
                    before: before,
                    after: after,
                    reason: reason
                )
            ],
            reasons: [reason],
            action: .replaceWorkout(
                workoutID: workout.id,
                replacement: after,
                generationReason: .availabilityChanged
            ),
            asOf: now
        )
    }

    private func previewUnavailableDay(
        _ date: Date,
        request: String,
        intent: CoachIntent,
        context: AthleteContextSnapshot,
        setup: AthleteSetup,
        plan: WeeklyPlan,
        reshaper: PlanReshaper,
        asOf now: Date
    ) -> CoachDomainResponse {
        do {
            try reshaper.validateWeek(plan, on: date, asOf: now)
        } catch {
            return noChange(
                (error as? LocalizedError)?.errorDescription
                    ?? "That day cannot be changed.",
                context: context
            )
        }

        guard let weekday = Weekday(date: date, calendar: calendar) else {
            return noChange("I could not resolve that training day.", context: context)
        }

        var temporary = setup.schedule
        if let index = temporary.days.firstIndex(where: { $0.weekday == weekday }) {
            temporary.days[index].isAvailable = false
        } else {
            temporary.days.append(
                TrainingAvailability(weekday: weekday, isAvailable: false)
            )
        }

        let outcome = reshaper.reshape(
            plan,
            schedule: temporary,
            preferences: setup.preferences,
            asOf: now
        )

        if outcome.isUnchanged {
            return noChange(
                "No unresolved future training needs to move after marking \(weekday.displayName) unavailable.",
                context: context
            )
        }

        let changes = outcome.changes.compactMap { change -> CoachWorkoutChange? in
            guard let workout = plan.workouts.first(where: { $0.id == change.workoutID }) else {
                return nil
            }
            let before = CoachWorkoutSnapshot(workout)
            var after = before
            after.date = change.date
            if change.skipped {
                after.status = .skipped
            }
            return CoachWorkoutChange(
                kind: change.skipped ? .skipped : .moved,
                before: before,
                after: after,
                reason: change.skipped
                    ? "No valid remaining day can hold this session without violating availability or spacing."
                    : "Moved to an available day that preserves the existing spacing and duration constraints."
            )
        }

        let reason = outcome.dropped > 0
            ? "\(outcome.dropped) session\(outcome.dropped == 1 ? "" : "s") cannot be safely relocated and would be skipped."
            : "All affected sessions can be relocated within the remaining week."

        return previewResponse(
            message: "Here is the deterministic remaining-week adjustment for making \(weekday.displayName) unavailable.",
            request: request,
            intent: intent,
            constraints: ["\(weekday.displayName) unavailable for this week"],
            context: context,
            plan: plan,
            changes: changes,
            reasons: [reason, "Completed, skipped, imported, and past sessions remain immutable."],
            action: .reshapeWeek(
                temporarySchedule: temporary,
                expectedChanges: outcome.changes.map(CoachReshapeExpectation.init)
            ),
            asOf: now
        )
    }

    private func previewMoveSession(
        from sourceDate: Date,
        to targetDate: Date,
        request: String,
        intent: CoachIntent,
        context: AthleteContextSnapshot,
        setup: AthleteSetup,
        plan: WeeklyPlan,
        reshaper: PlanReshaper,
        asOf now: Date
    ) -> CoachDomainResponse {
        guard let workout = plan.workout(on: sourceDate, calendar: calendar),
              workout.discipline.isTrainingSession else {
            return noChange("There is no training session to move on \(dayLabel(sourceDate)).", context: context)
        }
        guard reshaper.canEdit(workout, in: plan, asOf: now) else {
            return noChange("That workout is already part of history and cannot be moved.", context: context)
        }

        do {
            try reshaper.validatePlacement(
                workout,
                on: targetDate,
                in: plan,
                schedule: setup.schedule,
                asOf: now
            )
        } catch {
            return noChange(
                (error as? LocalizedError)?.errorDescription ?? "That move does not fit the current training constraints.",
                context: context
            )
        }

        let before = CoachWorkoutSnapshot(workout)
        var after = before
        after.date = calendar.startOfDay(for: targetDate)
        let reason = "The session content is unchanged; only its date moves after availability, duration, recovery, and spacing validation."

        return previewResponse(
            message: "I can move \(workout.title) from \(dayLabel(sourceDate)) to \(dayLabel(targetDate)).",
            request: request,
            intent: intent,
            constraints: ["Move one unresolved future session"],
            context: context,
            plan: plan,
            changes: [
                CoachWorkoutChange(kind: .moved, before: before, after: after, reason: reason)
            ],
            reasons: [reason],
            action: .moveWorkout(workoutID: workout.id, targetDate: after.date),
            asOf: now
        )
    }

    private func previewSkipSession(
        on date: Date,
        request: String,
        intent: CoachIntent,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        reshaper: PlanReshaper,
        asOf now: Date
    ) -> CoachDomainResponse {
        guard let workout = plan.workout(on: date, calendar: calendar),
              workout.discipline.isTrainingSession else {
            return noChange("There is no training session to skip on \(dayLabel(date)).", context: context)
        }
        guard reshaper.canEdit(workout, in: plan, asOf: now) else {
            return noChange("That workout is already part of history and cannot be skipped.", context: context)
        }

        let before = CoachWorkoutSnapshot(workout)
        var after = before
        after.status = .skipped
        let reason = "Only this unresolved future session is marked skipped; completed history and other sessions are unchanged."

        return previewResponse(
            message: "I can skip \(workout.title) on \(dayLabel(date)).",
            request: request,
            intent: intent,
            constraints: ["Skip one unresolved future session"],
            context: context,
            plan: plan,
            changes: [
                CoachWorkoutChange(kind: .skipped, before: before, after: after, reason: reason)
            ],
            reasons: [reason],
            action: .skipWorkout(workoutID: workout.id),
            asOf: now
        )
    }

    private func previewUnavailableRange(
        start: Date,
        end: Date,
        request: String,
        intent: CoachIntent,
        context: AthleteContextSnapshot,
        setup: AthleteSetup,
        plan: WeeklyPlan,
        reshaper: PlanReshaper,
        asOf now: Date
    ) -> CoachDomainResponse {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard endDay >= startDay else {
            return noChange("The unavailable period must end on or after its start date.", context: context)
        }

        let today = calendar.startOfDay(for: now)
        guard endDay >= today else {
            return noChange("That unavailable period is already in the past.", context: context)
        }

        let planStart = calendar.startOfDay(for: plan.startDate)
        let planEnd = calendar.startOfDay(for: plan.endDate)
        let effectiveStart = max(max(startDay, planStart), today)
        let effectiveEnd = min(endDay, planEnd)

        var temporary = setup.schedule
        var unavailableDays: [Weekday] = []
        if effectiveEnd >= effectiveStart {
            var cursor = effectiveStart
            while cursor <= effectiveEnd {
                if let weekday = Weekday(date: cursor, calendar: calendar) {
                    unavailableDays.append(weekday)
                    if let index = temporary.days.firstIndex(where: { $0.weekday == weekday }) {
                        temporary.days[index].isAvailable = false
                    } else {
                        temporary.days.append(TrainingAvailability(weekday: weekday, isAvailable: false))
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        let outcome = reshaper.reshape(
            plan,
            schedule: temporary,
            preferences: setup.preferences,
            asOf: now
        )

        let changes = outcome.changes.compactMap { change -> CoachWorkoutChange? in
            guard let workout = plan.workouts.first(where: { $0.id == change.workoutID }) else { return nil }
            let before = CoachWorkoutSnapshot(workout)
            var after = before
            after.date = change.date
            if change.skipped { after.status = .skipped }
            return CoachWorkoutChange(
                kind: change.skipped ? .skipped : .moved,
                before: before,
                after: after,
                reason: change.skipped
                    ? "No valid day remains inside this week after applying the temporary time-off window."
                    : "Moved outside the temporary unavailable window while preserving deterministic spacing and availability."
            )
        }

        let labels = Array(Set(unavailableDays.map(\.displayName))).sorted().joined(separator: ", ")
        var reasons: [String] = []
        if !labels.isEmpty {
            reasons.append("Temporary unavailable days in this week: \(labels).")
        } else {
            reasons.append("The time-off range starts after the current week, so this week's workouts stay unchanged.")
        }
        if endDay > planEnd {
            reasons.append("Future weeks generated during this range will automatically treat those dates as unavailable.")
        }

        return previewResponse(
            message: "Here is the deterministic current-week adjustment for your unavailable period.",
            request: request,
            intent: intent,
            constraints: ["Unavailable from \(dayLabel(startDay)) through \(dayLabel(endDay))"],
            context: context,
            plan: plan,
            changes: changes,
            reasons: reasons,
            action: .timeOffRange(
                start: startDay,
                end: endDay,
                temporarySchedule: temporary,
                expectedChanges: outcome.changes.map(CoachReshapeExpectation.init)
            ),
            asOf: now
        )
    }

    private func previewEasierSession(
        on date: Date,
        reason: CoachEaseReason,
        request: String,
        intent: CoachIntent,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        reshaper: PlanReshaper,
        asOf now: Date
    ) -> CoachDomainResponse {
        guard let workout = plan.workout(on: date, calendar: calendar),
              workout.discipline.isPlannedWorkout else {
            return noChange(
                "There is no active workout to make easier on \(dayLabel(date)).",
                context: context
            )
        }
        guard workout.discipline.isTrainingSession else {
            return noChange(
                "\(workout.title) is already a recovery-focused day.",
                context: context
            )
        }
        guard reshaper.canEdit(workout, in: plan, asOf: now) else {
            return noChange(
                "That workout is already part of history and will not be rewritten.",
                context: context
            )
        }

        if context.capability.recoveryState == CapabilityRecoveryState.needsAttention.rawValue {
            return recoveryOverridePreview(
                workout: workout,
                request: request,
                intent: intent,
                context: context,
                plan: plan,
                reason: "Recent recorded pain, symptoms, or recovery evidence requires a recovery substitution.",
                asOf: now
            )
        }

        guard let sport = workout.discipline.sport else {
            return recoveryOverridePreview(
                workout: workout,
                request: request,
                intent: intent,
                context: context,
                plan: plan,
                reason: "The multisport session cannot be volume-reduced safely as one sport, so recovery is the conservative substitution.",
                asOf: now
            )
        }

        let reduced = plan.parameters.applying(
            .reduceVolume(fraction: 0.20),
            to: sport
        )
        let replacement = PrescribedSessions.session(
            workout.discipline,
            on: workout.date,
            parameters: reduced,
            goal: "Keep the session easy today while reducing training volume."
        )
        let before = CoachWorkoutSnapshot(workout)
        let after = CoachWorkoutSnapshot(replacement)

        let userReason = switch reason {
        case .poorSleep: "You reported poor sleep."
        case .tired: "You reported feeling tired."
        case .general: "You asked for an easier session."
        }
        let explanation = "\(userReason) Athevia reduces the sport's existing primary volume variable by 20% without increasing intensity."

        return previewResponse(
            message: "I can make \(workout.title) easier while keeping its original purpose.",
            request: request,
            intent: intent,
            constraints: [userReason],
            context: context,
            plan: plan,
            changes: [
                CoachWorkoutChange(
                    kind: .eased,
                    before: before,
                    after: after,
                    reason: explanation
                )
            ],
            reasons: [explanation],
            action: .replaceWorkout(
                workoutID: workout.id,
                replacement: after,
                generationReason: .weeklyReduction
            ),
            asOf: now
        )
    }

    private func recoveryOverridePreview(
        workout: PlannedWorkout,
        request: String,
        intent: CoachIntent,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        reason: String,
        asOf now: Date
    ) -> CoachDomainResponse {
        let replacement = PrescribedSessions.recoveryDay(
            on: workout.date,
            goal: "Prioritize recovery today before adding more training load."
        )
        let before = CoachWorkoutSnapshot(workout)
        let after = CoachWorkoutSnapshot(replacement)

        return previewResponse(
            message: "Safety takes priority here. The valid change is to replace the training load with recovery.",
            request: request,
            intent: intent,
            constraints: ["Recovery safety override"],
            context: context,
            plan: plan,
            changes: [
                CoachWorkoutChange(
                    kind: .eased,
                    before: before,
                    after: after,
                    reason: reason
                )
            ],
            reasons: [reason],
            action: .replaceWorkout(
                workoutID: workout.id,
                replacement: after,
                generationReason: .recovery
            ),
            asOf: now
        )
    }

    private func prepareFor5K(
        eventDate: Date?,
        request: String,
        intent: CoachIntent,
        context: AthleteContextSnapshot,
        setup: AthleteSetup,
        plan: WeeklyPlan,
        plans: [WeeklyPlan],
        reshaper: PlanReshaper,
        asOf now: Date
    ) -> CoachDomainResponse {
        let running = context.capability.sports.first { $0.sport == .running }
        let evidence: String
        if let recent = running?.recentAverageMeters {
            evidence = "Recent recorded runs average \(distanceLabel(recent)); the recent best is \(running?.recentBestMeters.map(distanceLabel) ?? "not available")."
        } else if let baseline = running?.baselineMeters {
            evidence = "There is not enough recent recorded running distance, so the \(distanceLabel(baseline)) onboarding reference remains weaker context."
        } else {
            evidence = "There is not enough running evidence yet to estimate current 5K readiness."
        }

        guard let eventDate else {
            return CoachDomainResponse(
                message: "\(evidence) I can use this history to prepare a 5K plan, but an event date is material to taper and race-week logic. Tell me the date before I propose changing your goal.",
                evidenceSummary: evidenceSummary(context),
                preview: nil
            )
        }

        guard calendar.startOfDay(for: eventDate) >= calendar.startOfDay(for: now) else {
            return noChange("The 5K event date must be today or later.", context: context)
        }
        guard setup.selectedSports.contains(.running) else {
            return noChange(
                "Running is not in the current training mix. Add running first so the existing planner can validate a 5K event goal.",
                context: context
            )
        }

        let beforeObjective = setup.objective
        let afterObjective = TrainingObjective.event(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventDate: eventDate,
            targetIntent: .complete
        )
        let issues = TrainingObjectiveValidator.issues(
            for: afterObjective,
            selectedSports: setup.selectedSports,
            asOf: now,
            calendar: calendar
        )
        guard issues.isEmpty else {
            return noChange(
                issues.map(\.message).joined(separator: " "),
                context: context
            )
        }

        var candidateSetup = setup
        candidateSetup.objective = afterObjective
        let candidate = candidateWeek(
            setup: candidateSetup,
            currentPlan: plan,
            plans: plans,
            asOf: now
        )

        let changes = compareFuture(
            current: plan,
            candidate: candidate,
            reshaper: reshaper,
            asOf: now
        )
        let dateText = dayLabel(eventDate)
        let reason = "The existing Journey and weekly generator recompute phase, readiness, sport priority, event-specific work, taper, and race week from a structured 5K goal dated \(dateText)."

        return previewResponse(
            message: "\(evidence) Here is the upcoming-plan preview for using \(dateText) as a 5K event goal.",
            request: request,
            intent: intent,
            constraints: ["5K run", "Event date \(dateText)", "Complete target"],
            context: context,
            plan: plan,
            changes: changes,
            reasons: [reason, "This changes the event goal only after Apply; completed history remains untouched."],
            action: .changeObjective(
                before: beforeObjective,
                after: afterObjective
            ),
            asOf: now
        )
    }

    private func candidateWeek(
        setup: AthleteSetup,
        currentPlan: WeeklyPlan,
        plans: [WeeklyPlan],
        asOf now: Date
    ) -> WeeklyPlan {
        let capability = AthleteCapabilityAssessmentBuilder(calendar: calendar)
            .build(setup: setup, plans: plans, asOf: now)

        var generator = WeeklyPlanGenerator()
        generator.calendar = calendar
        generator.schedule = setup.schedule
        generator.preferences = setup.preferences
        generator.capability = capability
        generator.journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, capability: capability, asOf: now)
        generator.objective = setup.objective
        generator.openWaterConsent = setup.openWaterTrainingConsent
        generator.eventState = setup.eventState

        let previousStart = calendar.date(
            byAdding: .day,
            value: -7,
            to: currentPlan.startDate
        ) ?? currentPlan.startDate
        let previousEnd = calendar.date(
            byAdding: .day,
            value: -1,
            to: currentPlan.startDate
        ) ?? currentPlan.startDate

        let seed = WeeklyPlan(
            weekNumber: currentPlan.weekNumber - 1,
            startDate: previousStart,
            endDate: previousEnd,
            status: .completed,
            parameters: currentPlan.parameters,
            workouts: []
        )
        let neutral = WeeklyAnalysis(
            weekNumber: seed.weekNumber,
            startDate: seed.startDate,
            endDate: seed.endDate,
            plannedSessions: 0,
            completedSessions: 0,
            skippedSessions: 0,
            sports: []
        )
        return generator.generate(after: seed, analysis: neutral)
    }

    private func compareFuture(
        current: WeeklyPlan,
        candidate: WeeklyPlan,
        reshaper: PlanReshaper,
        asOf now: Date
    ) -> [CoachWorkoutChange] {
        let boundary = calendar.startOfDay(for: now)
        let immutableDays = current.orderedWorkouts.filter {
            calendar.startOfDay(for: $0.date) >= boundary
                && !(reshaper.isUnrecorded($0) && $0.origin == .generated)
        }.map { calendar.startOfDay(for: $0.date) }

        let currentMutable = current.orderedWorkouts.filter {
            calendar.startOfDay(for: $0.date) >= boundary
                && reshaper.isUnrecorded($0)
                && $0.origin == .generated
        }
        let candidateMutable = candidate.orderedWorkouts.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= boundary
                && !immutableDays.contains(where: { calendar.isDate($0, inSameDayAs: day) })
        }

        let allDays = Set(
            currentMutable.map { calendar.startOfDay(for: $0.date) }
                + candidateMutable.map { calendar.startOfDay(for: $0.date) }
        )

        return allDays.sorted().compactMap { day in
            let before = currentMutable.first { calendar.isDate($0.date, inSameDayAs: day) }
                .map(CoachWorkoutSnapshot.init)
            let after = candidateMutable.first { calendar.isDate($0.date, inSameDayAs: day) }
                .map(CoachWorkoutSnapshot.init)

            guard comparable(before) != comparable(after) else { return nil }
            return CoachWorkoutChange(
                kind: .replanned,
                before: before,
                after: after,
                reason: "Recomputed by the deterministic planner for the new event objective."
            )
        }
    }

    private func comparable(_ snapshot: CoachWorkoutSnapshot?) -> String? {
        guard let snapshot else { return nil }
        struct ComparableSnapshot: Codable {
            let date: Date
            let discipline: Discipline
            let title: String
            let goal: String
            let targetRPE: RPERange?
            let duration: TimeInterval?
            let distance: Double?
            let structure: WorkoutStructure
        }
        return CoachStableFingerprint.value(
            for: ComparableSnapshot(
                date: snapshot.date,
                discipline: snapshot.discipline,
                title: snapshot.title,
                goal: snapshot.goal,
                targetRPE: snapshot.targetRPE,
                duration: snapshot.prescribedDurationSeconds,
                distance: snapshot.targetDistanceMeters,
                structure: snapshot.structure
            )
        )
    }

    // MARK: - Response helpers

    private func previewResponse(
        message: String,
        request: String,
        intent: CoachIntent,
        constraints: [String],
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        changes: [CoachWorkoutChange],
        reasons: [String],
        action: CoachPlanAction,
        asOf now: Date
    ) -> CoachDomainResponse {
        CoachDomainResponse(
            message: message,
            evidenceSummary: evidenceSummary(context),
            preview: CoachPlanChangePreview(
                originalRequest: request,
                interpretedIntent: intent,
                interpretedConstraints: constraints,
                athleteScopeID: context.athleteScopeID,
                contextVersion: context.version,
                basePlanVersion: CoachPlanVersion.fingerprint(plan),
                planID: plan.id,
                generatedAt: now,
                changes: changes,
                reasons: reasons,
                action: action,
                validation: .valid(
                    at: now,
                    checks: [
                        "Deterministic domain validation passed for this preview.",
                        "Only eligible future plan state is represented by the action.",
                        "Apply will revalidate athlete scope, evidence version and base-plan version."
                    ]
                )
            )
        )
    }

    private func noChange(
        _ message: String,
        context: AthleteContextSnapshot
    ) -> CoachDomainResponse {
        CoachDomainResponse(
            message: message,
            evidenceSummary: evidenceSummary(context),
            preview: nil
        )
    }

    private func evidenceSummary(_ context: AthleteContextSnapshot) -> String {
        var summary = "Data used: \(context.evidencePeriodLabel); \(context.recentHealthWorkouts.count) recent Apple Health workout\(context.recentHealthWorkouts.count == 1 ? "" : "s")."
        if let caveat = context.caveats.first {
            summary += " \(caveat)"
        }
        return summary
    }

    private func parameterChanges(
        from first: TrainingParameters,
        to last: TrainingParameters
    ) -> [String] {
        var changes: [String] = []

        if first.runIsContinuous != last.runIsContinuous {
            changes.append(last.runIsContinuous
                ? "Running progressed from run/walk intervals to continuous running."
                : "Running returned to run/walk structure.")
        } else if last.runIsContinuous,
                  first.runContinuousSeconds != last.runContinuousSeconds {
            changes.append(
                "Continuous running changed from \(minuteLabel(first.runContinuousSeconds)) to \(minuteLabel(last.runContinuousSeconds))."
            )
        } else if first.runIntervalSeconds != last.runIntervalSeconds
                    || first.runRepeatCount != last.runRepeatCount {
            changes.append(
                "Run intervals changed from \(first.runRepeatCount) × \(Int(first.runIntervalSeconds))s to \(last.runRepeatCount) × \(Int(last.runIntervalSeconds))s."
            )
        }

        if first.rideWorkSeconds != last.rideWorkSeconds {
            changes.append(
                "Cycling work changed from \(minuteLabel(first.rideWorkSeconds)) to \(minuteLabel(last.rideWorkSeconds))."
            )
        }

        if first.swimRepeatDistanceMeters != last.swimRepeatDistanceMeters
            || first.swimTotalMeters != last.swimTotalMeters {
            changes.append(
                "Swimming changed from \(Int(first.swimRepeatDistanceMeters)) m repeats / \(Int(first.swimTotalMeters)) m total to \(Int(last.swimRepeatDistanceMeters)) m repeats / \(Int(last.swimTotalMeters)) m total."
            )
        }

        return changes
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func distanceLabel(_ meters: Double) -> String {
        meters >= 1_000
            ? String(format: "%.1f km", meters / 1_000)
            : "\(Int(meters.rounded())) m"
    }

    private func minuteLabel(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }
}
