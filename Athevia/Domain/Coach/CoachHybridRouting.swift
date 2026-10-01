import Foundation

struct CoachHybridRouting: Sendable {
    var calendar: Calendar = .current

    func intent(
        from remote: CoachLLMDeterministicIntent,
        plan: WeeklyPlan
    ) -> CoachIntent? {
        switch remote.kind {
        case .moveSession:
            guard let source = date(remote.sourceDateISO),
                  let target = date(remote.targetDateISO) else { return nil }
            return .moveSession(from: source, to: target)

        case .skipSession:
            guard let target = date(remote.sourceDateISO ?? remote.targetDateISO) else { return nil }
            return .skipSession(date: target)

        case .unavailable:
            guard let target = date(remote.targetDateISO ?? remote.sourceDateISO) else { return nil }
            return .unavailable(date: target)

        case .unavailableRange:
            guard let start = date(remote.sourceDateISO ?? remote.targetDateISO),
                  let end = date(remote.endDateISO),
                  end >= start else { return nil }
            return .unavailableRange(start: start, end: end)

        case .limitSession:
            guard let target = date(remote.targetDateISO ?? remote.sourceDateISO),
                  let minutes = remote.maxMinutes,
                  (10...240).contains(minutes) else { return nil }
            return .limitSession(date: target, maxMinutes: minutes)

        case .easeSession:
            guard let target = date(remote.targetDateISO ?? remote.sourceDateISO) else { return nil }
            return .easeSession(date: target, reason: remote.easeReason ?? .general)
        }
    }

    func workoutPreview(
        proposal: CoachLLMWorkoutProposal,
        request: String,
        context: AthleteContextSnapshot,
        setup: AthleteSetup,
        plan: WeeklyPlan,
        asOf now: Date
    ) -> CoachDomainResponse {
        guard context.availableSports.contains(proposal.sport) else {
            return response(
                "That sport is not enabled in your current training setup, so I did not add it.",
                context: context
            )
        }
        guard context.capability.recoveryState != CapabilityRecoveryState.needsAttention.rawValue else {
            return response(
                "Your recent recovery evidence requires a cautious path, so I will not add another training session right now.",
                context: context
            )
        }
        guard let proposedDate = date(proposal.dateISO) else {
            return response("I could not resolve a safe date for that workout.", context: context)
        }

        let targetDate = calendar.startOfDay(for: proposedDate)
        guard targetDate >= calendar.startOfDay(for: now),
              plan.contains(targetDate, calendar: calendar) else {
            return response(
                "The generated workout needs a date inside the current training week from today onward.",
                context: context
            )
        }

        let discipline: Discipline
        switch proposal.sport {
        case .running: discipline = .running
        case .cycling: discipline = .cycling
        case .swimming: discipline = .swimming
        }

        let weekday = Weekday(date: targetDate, calendar: calendar)
        let availability = weekday.map { setup.schedule.availability(on: $0) }
        guard availability?.isAvailable == true else {
            return response("That generated date is not available in your schedule.", context: context)
        }

        let requestedMinutes = min(
            proposal.targetMinutes,
            availability?.maxDurationMinutes ?? proposal.targetMinutes
        )

        var parameters = plan.parameters
        if proposal.sport != .swimming {
            // A generated workout may fit inside the current prescription, but
            // the model cannot increase training load beyond deterministic dials.
            parameters = parameters.capped(toTrainingMinutes: requestedMinutes)
        } else if availability?.maxDurationMinutes != nil {
            return response(
                "I can analyze or suggest a swim, but I will not convert swim distance into a time-limited prescription without measured pace evidence.",
                context: context
            )
        }

        let candidate = PrescribedSessions.session(
            discipline,
            on: targetDate,
            parameters: parameters,
            goal: proposal.goal
        )
        candidate.origin = .generated

        var reshaper = PlanReshaper()
        reshaper.calendar = calendar
        do {
            try reshaper.validatePlacement(
                candidate,
                on: targetDate,
                in: plan,
                schedule: setup.schedule,
                asOf: now
            )
        } catch {
            return response(
                (error as? LocalizedError)?.errorDescription
                    ?? "That workout does not fit safely into the current week.",
                context: context
            )
        }

        let snapshot = CoachWorkoutSnapshot(candidate)
        let intent = CoachIntent.generateWorkout(
            sport: proposal.sport,
            date: targetDate,
            maxMinutes: requestedMinutes
        )
        let reason = "Generated from your recent training context, then rebuilt and validated by Athevia's deterministic prescription engine."
        let preview = CoachPlanChangePreview(
            originalRequest: request,
            interpretedIntent: intent,
            interpretedConstraints: [
                "Sport: \(proposal.sport.displayName)",
                "Focus: \(proposal.focus.rawValue)",
                "Time ceiling: \(requestedMinutes) minutes",
                "Date: \(TrainingFormatter.shortDate(targetDate))"
            ],
            athleteScopeID: context.athleteScopeID,
            contextVersion: context.version,
            basePlanVersion: CoachPlanVersion.fingerprint(plan),
            planID: plan.id,
            generatedAt: now,
            changes: [
                CoachWorkoutChange(
                    kind: .replanned,
                    before: nil,
                    after: snapshot,
                    reason: reason
                )
            ],
            reasons: [reason],
            action: .addWorkout(
                workout: snapshot,
                generationReason: .coachAdjustment
            ),
            validation: .valid(
                at: now,
                checks: [
                    "Current-week date",
                    "Athlete availability",
                    "No occupied training day",
                    "Recovery and spacing policy",
                    "Existing deterministic training parameters"
                ]
            )
        )

        return CoachDomainResponse(
            message: "I built a \(proposal.sport.displayName.lowercased()) session from your current training parameters. Review it before anything changes.",
            evidenceSummary: "The model chose the high-level workout purpose; Athevia built and validated the actual prescription.",
            preview: preview
        )
    }

    private func response(
        _ message: String,
        context: AthleteContextSnapshot
    ) -> CoachDomainResponse {
        CoachDomainResponse(
            message: message,
            evidenceSummary: "Training context: \(context.evidencePeriodLabel).",
            preview: nil
        )
    }

    private func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso).map { calendar.startOfDay(for: $0) }
    }
}
