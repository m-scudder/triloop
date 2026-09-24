import Foundation

enum TrainingPhase: String, Codable, CaseIterable, Sendable {
    case foundation
    case build
    case specific
    case taper
    case raceWeek
    case recovery

    var displayName: String {
        switch self {
        case .foundation: "Foundation"
        case .build: "Build"
        case .specific: "Specific"
        case .taper: "Taper"
        case .raceWeek: "Race Week"
        case .recovery: "Post Event / Recovery"
        }
    }
}

enum EventReadinessStatus: String, Codable, Sendable {
    case notEnoughData
    case building
    case onTrack
    case needsAttention
    case eventReady

    var displayName: String {
        switch self {
        case .notEnoughData: "Not enough data"
        case .building: "Building"
        case .onTrack: "On track"
        case .needsAttention: "Needs attention"
        case .eventReady: "Event ready"
        }
    }
}

enum ReadinessGap: Equatable, Sendable {
    case runningContinuity
    case runningEndurance
    case swimContinuity(currentMeters: Double, targetMeters: Double)
    case cyclingEndurance(currentMinutes: Int)
    case brickExperience
    case insufficientRecentEvidence

    var message: String {
        switch self {
        case .runningContinuity: "Build continuous running before race-specific work."
        case .runningEndurance: "Build running endurance toward the event distance."
        case .swimContinuity(let current, let target):
            "Build continuous swimming from \(Int(current)) m toward \(Int(target)) m."
        case .cyclingEndurance(let minutes): "Build cycling endurance beyond the current \(minutes)-minute baseline."
        case .brickExperience: "Add bike-to-run transition practice."
        case .insufficientRecentEvidence: "Complete and report more sessions to improve readiness confidence."
        }
    }
}

struct SportReadiness: Equatable, Sendable, Identifiable {
    var sport: Sport
    var status: EventReadinessStatus
    var gaps: [ReadinessGap]
    var id: Sport { sport }
}

struct EventReadiness: Equatable, Sendable {
    var status: EventReadinessStatus
    var sports: [SportReadiness]
}

enum WeeklyTrainingObjectiveKind: String, Codable, Sendable {
    case runWalkContinuity
    case continuousRunning
    case endurance
    case swimContinuity
    case swimTechnique
    case brickTransition
    case racePacing
    case taper
    case recovery
    case consistency

    var displayName: String {
        switch self {
        case .runWalkContinuity: "Build run/walk continuity"
        case .continuousRunning: "Build continuous running"
        case .endurance: "Build endurance"
        case .swimContinuity: "Build swim continuity"
        case .swimTechnique: "Improve swim technique"
        case .brickTransition: "Practice bike-to-run transition"
        case .racePacing: "Practice event pacing"
        case .taper: "Reduce load, keep rhythm"
        case .recovery: "Recover"
        case .consistency: "Build consistency"
        }
    }
}

struct WeeklyTrainingObjective: Equatable, Sendable, Identifiable {
    var sport: Sport?
    var kind: WeeklyTrainingObjectiveKind
    var priority: Int
    var id: String { "\(sport?.rawValue ?? "all")-\(kind.rawValue)-\(priority)" }
}

struct SportPriority: Equatable, Sendable, Identifiable {
    var sport: Sport
    var rank: Int
    var reason: String
    var id: Sport { sport }
}

struct TrainingJourney: Equatable, Sendable {
    var phase: TrainingPhase
    var weeksRemaining: Int?
    var readiness: EventReadiness
    var weeklyObjectives: [WeeklyTrainingObjective]
    var sportPriorities: [SportPriority]

    var primaryFocus: WeeklyTrainingObjective? {
        weeklyObjectives.min { $0.priority < $1.priority }
    }
}

struct TrainingJourneyPolicy: Equatable, Sendable {
    struct PhaseThresholds: Equatable, Sendable {
        var foundationMinimumWeeks: Int
        var specificStartsAtWeeksRemaining: Int
        var taperStartsAtWeeksRemaining: Int
    }

    func thresholds(for event: AthleteEventGoal) -> PhaseThresholds {
        switch event.distance?.kind {
        case .run5K, .swimming500M, .cycling20K, .triathlonSuperSprint:
            PhaseThresholds(foundationMinimumWeeks: 6, specificStartsAtWeeksRemaining: 4, taperStartsAtWeeksRemaining: 1)
        case .run10K, .swimming1K, .cycling50K, .triathlonSprint:
            PhaseThresholds(foundationMinimumWeeks: 8, specificStartsAtWeeksRemaining: 5, taperStartsAtWeeksRemaining: 2)
        case .runHalfMarathon, .swimming2K, .cycling100K, .triathlonOlympic:
            PhaseThresholds(foundationMinimumWeeks: 10, specificStartsAtWeeksRemaining: 6, taperStartsAtWeeksRemaining: 2)
        case .runMarathon, .triathlon703:
            PhaseThresholds(foundationMinimumWeeks: 14, specificStartsAtWeeksRemaining: 8, taperStartsAtWeeksRemaining: 3)
        case .runCustom, .swimmingCustom, .cyclingCustom, .triathlonCustom, .none:
            PhaseThresholds(foundationMinimumWeeks: 8, specificStartsAtWeeksRemaining: 5, taperStartsAtWeeksRemaining: 2)
        }
    }

    func phase(for event: AthleteEventGoal, baseline: AthleteBaseline, asOf date: Date, calendar: Calendar) -> TrainingPhase {
        guard let days = event.daysRemaining(asOf: date, calendar: calendar) else { return .foundation }
        if days < 0 { return .recovery }
        if days <= 7 { return .raceWeek }

        let weeks = event.weeksRemaining(asOf: date, calendar: calendar) ?? 0
        let rules = thresholds(for: event)
        if weeks <= rules.taperStartsAtWeeksRemaining { return .taper }
        if weeks <= rules.specificStartsAtWeeksRemaining { return .specific }

        if needsFoundation(event: event, baseline: baseline) { return .foundation }
        return .build
    }

    private func needsFoundation(event: AthleteEventGoal, baseline: AthleteBaseline) -> Bool {
        switch event.sport {
        case .running: !baseline.running.runsContinuously
        case .swimming: (baseline.swimming.continuousMeters ?? 0) < min(event.distance?.components.swimMeters ?? 200, 200)
        case .cycling: baseline.cycling.comfortableMinutes < 30
        case .triathlon:
            !baseline.running.runsContinuously
                || (baseline.swimming.continuousMeters ?? 0) < 100
                || baseline.cycling.comfortableMinutes < 30
        }
    }
}

struct TrainingJourneyPlanner: Sendable {
    var policy = TrainingJourneyPolicy()
    var calendar: Calendar = .current

    func plan(
        setup: AthleteSetup,
        recentPlans: [WeeklyPlan] = [],
        asOf date: Date = .now
    ) -> TrainingJourney {
        guard setup.objective.kind == .event, let event = setup.objective.event else {
            return generalJourney(setup: setup)
        }

        let phase = policy.phase(for: event, baseline: setup.baseline, asOf: date, calendar: calendar)
        let readiness = readiness(for: event, baseline: setup.baseline, recentPlans: recentPlans)
        let priorities = priorities(for: event, baseline: setup.baseline)
        let objectives = objectives(for: event, baseline: setup.baseline, phase: phase, priorities: priorities)

        return TrainingJourney(
            phase: phase,
            weeksRemaining: event.weeksRemaining(asOf: date, calendar: calendar),
            readiness: readiness,
            weeklyObjectives: objectives,
            sportPriorities: priorities
        )
    }

    private func generalJourney(setup: AthleteSetup) -> TrainingJourney {
        let sports = setup.selectedSports
        return TrainingJourney(
            phase: .foundation,
            weeksRemaining: nil,
            readiness: EventReadiness(
                status: .notEnoughData,
                sports: sports.map { SportReadiness(sport: $0, status: .notEnoughData, gaps: [.insufficientRecentEvidence]) }
            ),
            weeklyObjectives: [WeeklyTrainingObjective(sport: nil, kind: .consistency, priority: 1)],
            sportPriorities: sports.enumerated().map {
                SportPriority(sport: $0.element, rank: $0.offset + 1, reason: "Selected training sport")
            }
        )
    }

    private func readiness(
        for event: AthleteEventGoal,
        baseline: AthleteBaseline,
        recentPlans: [WeeklyPlan]
    ) -> EventReadiness {
        let sports = event.sport.requiredTrainingSports.map { sport -> SportReadiness in
            var gaps: [ReadinessGap] = []
            switch sport {
            case .running:
                if !baseline.running.runsContinuously { gaps.append(.runningContinuity) }
                else if event.distance?.components.runMeters ?? 0 > 5_000, baseline.running != .regular5K {
                    gaps.append(.runningEndurance)
                }
            case .swimming:
                let current = baseline.swimming.continuousMeters ?? 0
                let target = event.distance?.components.swimMeters ?? 0
                if target > 0, current < target { gaps.append(.swimContinuity(currentMeters: current, targetMeters: target)) }
            case .cycling:
                if baseline.cycling.comfortableMinutes < 45 { gaps.append(.cyclingEndurance(currentMinutes: baseline.cycling.comfortableMinutes)) }
            }
            if recentPlans.isEmpty { gaps.append(.insufficientRecentEvidence) }
            let status: EventReadinessStatus = gaps.isEmpty ? .onTrack : .building
            return SportReadiness(sport: sport, status: status, gaps: gaps)
        }

        let status: EventReadinessStatus
        if recentPlans.isEmpty { status = .notEnoughData }
        else if sports.contains(where: { !$0.gaps.isEmpty }) { status = .building }
        else { status = .onTrack }
        return EventReadiness(status: status, sports: sports)
    }

    private func priorities(for event: AthleteEventGoal, baseline: AthleteBaseline) -> [SportPriority] {
        let scored = event.sport.requiredTrainingSports.map { sport -> (Sport, Int, String) in
            switch sport {
            case .running:
                let score = baseline.running.runsContinuously ? (baseline.running == .regular5K ? 0 : 1) : 3
                return (sport, score, score >= 3 ? "Running continuity is the largest current gap." : "Maintain and extend running endurance.")
            case .swimming:
                let current = baseline.swimming.continuousMeters ?? 0
                let target = event.distance?.components.swimMeters ?? 500
                let ratio = target > 0 ? current / target : 1
                let score = ratio < 0.15 ? 4 : ratio < 0.5 ? 3 : ratio < 1 ? 2 : 0
                return (sport, score, score >= 3 ? "Swim continuity is the largest current gap." : "Maintain and extend swim continuity.")
            case .cycling:
                let score = baseline.cycling.comfortableMinutes < 30 ? 3 : baseline.cycling.comfortableMinutes < 60 ? 1 : 0
                return (sport, score, score >= 3 ? "Cycling endurance needs additional development." : "Maintain and extend cycling endurance.")
            }
        }

        return scored
            .sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.rawValue < rhs.0.rawValue : lhs.1 > rhs.1 }
            .enumerated()
            .map { SportPriority(sport: $0.element.0, rank: $0.offset + 1, reason: $0.element.2) }
    }

    private func objectives(
        for event: AthleteEventGoal,
        baseline: AthleteBaseline,
        phase: TrainingPhase,
        priorities: [SportPriority]
    ) -> [WeeklyTrainingObjective] {
        if phase == .recovery { return [.init(sport: nil, kind: .recovery, priority: 1)] }
        if phase == .taper || phase == .raceWeek { return [.init(sport: nil, kind: .taper, priority: 1)] }

        return priorities.map { priority in
            let kind: WeeklyTrainingObjectiveKind
            switch priority.sport {
            case .running:
                kind = baseline.running.runsContinuously ? (phase == .specific ? .racePacing : .endurance) : .runWalkContinuity
            case .swimming:
                kind = (baseline.swimming.continuousMeters ?? 0) < (event.distance?.components.swimMeters ?? 200)
                    ? .swimContinuity : .swimTechnique
            case .cycling:
                kind = .endurance
            }
            return WeeklyTrainingObjective(sport: priority.sport, kind: kind, priority: priority.rank)
        } + (event.sport == .triathlon && phase == .specific
            ? [WeeklyTrainingObjective(sport: nil, kind: .brickTransition, priority: priorities.count + 1)]
            : [])
    }
}
