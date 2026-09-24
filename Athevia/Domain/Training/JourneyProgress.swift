import Foundation

enum JourneyMilestoneKind: String, Codable, Sendable {
    case firstSession
    case firstContinuousRun
    case firstFiveK
    case swimContinuity
    case firstBrick
    case consistency
    case eventWeek
    case eventCompleted

    var displayName: String {
        switch self {
        case .firstSession: "First session completed"
        case .firstContinuousRun: "Continuous running unlocked"
        case .firstFiveK: "First 5K completed"
        case .swimContinuity: "Swim continuity improved"
        case .firstBrick: "First brick completed"
        case .consistency: "Consistent training"
        case .eventWeek: "Event week reached"
        case .eventCompleted: "Event journey completed"
        }
    }
}

struct JourneyMilestone: Identifiable, Equatable, Sendable {
    var kind: JourneyMilestoneKind
    var achievedAt: Date
    var detail: String
    var id: String { "\(kind.rawValue)-\(achievedAt.timeIntervalSince1970)" }
}

struct CapabilityRequirement: Identifiable, Equatable, Sendable {
    enum State: String, Sendable {
        case demonstrated
        case developing
        case notEnoughData

        var displayName: String {
            switch self {
            case .demonstrated: "Demonstrated"
            case .developing: "Developing"
            case .notEnoughData: "Not enough data"
            }
        }
    }

    var sport: Sport
    var requirement: String
    var currentEvidence: String
    var state: State
    var id: String { "\(sport.rawValue)-\(requirement)" }
}

struct JourneyProgressSnapshot: Equatable, Sendable {
    var journey: TrainingJourney
    var capabilities: [CapabilityRequirement]
    var milestones: [JourneyMilestone]
    var nextAction: String
}

struct JourneyProgressBuilder: Sendable {
    var calendar: Calendar = .current

    func build(
        setup: AthleteSetup,
        plans: [WeeklyPlan],
        asOf date: Date = .now
    ) -> JourneyProgressSnapshot {
        let recent = Array(plans.sorted { $0.startDate < $1.startDate }.suffix(4))
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, recentPlans: recent, asOf: date)

        return JourneyProgressSnapshot(
            journey: journey,
            capabilities: capabilities(setup: setup, plans: plans),
            milestones: milestones(setup: setup, plans: plans, asOf: date),
            nextAction: nextAction(for: journey)
        )
    }

    private func capabilities(setup: AthleteSetup, plans: [WeeklyPlan]) -> [CapabilityRequirement] {
        guard let event = setup.objective.event else { return [] }

        return event.sport.requiredTrainingSports.map { sport in
            switch sport {
            case .running:
                let target = event.distance?.components.runMeters ?? 0
                let best = bestDistance(.running, plans: plans)
                return CapabilityRequirement(
                    sport: .running,
                    requirement: target > 0 ? "\(distance(target)) run" : "Continuous running",
                    currentEvidence: best > 0 ? "Longest recorded: \(distance(best))" : baselineRun(setup.baseline.running),
                    state: target > 0 && best >= target ? .demonstrated
                        : (best > 0 || setup.baseline.running.runsContinuously ? .developing : .notEnoughData)
                )
            case .swimming:
                let target = event.distance?.components.swimMeters ?? 0
                let best = max(
                    bestDistance(.swimming, plans: plans),
                    setup.baseline.swimming.continuousMeters ?? 0
                )
                return CapabilityRequirement(
                    sport: .swimming,
                    requirement: target > 0 ? "\(distance(target)) swim" : "Continuous swimming",
                    currentEvidence: best > 0 ? "Continuous evidence: \(distance(best))" : "No continuous swim evidence yet",
                    state: target > 0 && best >= target ? .demonstrated : (best > 0 ? .developing : .notEnoughData)
                )
            case .cycling:
                let target = event.distance?.components.cycleMeters ?? 0
                let best = bestDistance(.cycling, plans: plans)
                return CapabilityRequirement(
                    sport: .cycling,
                    requirement: target > 0 ? "\(distance(target)) ride" : "Endurance riding",
                    currentEvidence: best > 0 ? "Longest recorded: \(distance(best))" : "\(setup.baseline.cycling.comfortableMinutes) min comfortable",
                    state: target > 0 && best >= target ? .demonstrated
                        : (best > 0 || setup.baseline.cycling.comfortableMinutes > 0 ? .developing : .notEnoughData)
                )
            }
        }
    }

    private func milestones(setup: AthleteSetup, plans: [WeeklyPlan], asOf date: Date) -> [JourneyMilestone] {
        let completed = plans.flatMap(\.trainingSessions).filter(\.isCompleted)
        var result: [JourneyMilestone] = []

        if let first = completed.min(by: { ($0.completedAt ?? $0.date) < ($1.completedAt ?? $1.date) }) {
            result.append(.init(kind: .firstSession, achievedAt: first.completedAt ?? first.date, detail: first.title))
        }

        if let run = completed
            .filter({ $0.discipline == .running && ($0.importedSummary?.distanceMeters ?? 0) >= 5_000 })
            .min(by: { $0.date < $1.date }) {
            result.append(.init(kind: .firstFiveK, achievedAt: run.completedAt ?? run.date, detail: "5 km running evidence recorded"))
        }

        if let brick = completed
            .filter({ $0.title == "Bike + Run Brick" })
            .min(by: { $0.date < $1.date }) {
            result.append(.init(kind: .firstBrick, achievedAt: brick.completedAt ?? brick.date, detail: "Bike-to-run transition completed"))
        }

        let reportedWeeks = plans.filter { $0.prescribedTrainingSessions.filter(\.hasReport).count >= 2 }
        if reportedWeeks.count >= 3, let third = reportedWeeks.sorted(by: { $0.startDate < $1.startDate }).dropFirst(2).first {
            result.append(.init(kind: .consistency, achievedAt: third.endDate, detail: "Three training weeks with reported sessions"))
        }

        if let event = setup.objective.event, let eventDate = event.eventDate {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: eventDate)
            ).day ?? 0
            if (0...7).contains(days) {
                result.append(.init(kind: .eventWeek, achievedAt: date, detail: "Event week"))
            } else if days < 0 {
                result.append(.init(kind: .eventCompleted, achievedAt: eventDate, detail: event.displayName))
            }
        }

        return result.sorted { $0.achievedAt < $1.achievedAt }
    }

    private func nextAction(for journey: TrainingJourney) -> String {
        if journey.phase == .recovery { return "Recover before starting the next objective." }
        if journey.phase == .raceWeek { return "Keep training light and follow the race-week plan." }
        if let gap = journey.readiness.sports.flatMap(\.gaps).first(where: { $0 != .insufficientRecentEvidence }) {
            return gap.message
        }
        if let focus = journey.primaryFocus { return focus.kind.displayName + "." }
        return "Complete and report the next prescribed session."
    }

    private func bestDistance(_ sport: Sport, plans: [WeeklyPlan]) -> Double {
        plans.flatMap(\.trainingSessions)
            .filter { $0.discipline.sport == sport && $0.isCompleted }
            .compactMap { $0.importedSummary?.distanceMeters }
            .max() ?? 0
    }

    private func distance(_ meters: Double) -> String {
        meters >= 1_000
            ? String(format: "%.1f km", meters / 1_000)
            : "\(Int(meters.rounded())) m"
    }

    private func baselineRun(_ baseline: RunningBaseline) -> String {
        baseline.runsContinuously ? "Continuous running reported" : "Run/walk baseline"
    }
}
