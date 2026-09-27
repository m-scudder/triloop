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
        case .foundation: "Getting Started"
        case .build: "Build Stamina"
        case .specific: "Practice for Your Event"
        case .taper: "Ease Off Before Your Event"
        case .raceWeek: "Event Week"
        case .recovery: "Recover After Your Event"
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
    case cyclingDistance(currentMeters: Double, targetMeters: Double)
    case brickExperience
    case trainingConsistency
    case insufficientRecentEvidence

    var message: String {
        switch self {
        case .runningContinuity:
            "Build continuous running before race-specific work."
        case .runningEndurance:
            "Build running endurance toward the event distance."
        case .swimContinuity(let current, let target):
            current > 0
                ? "Build continuous swimming from \(Int(current)) m toward \(Int(target)) m."
                : "Build verified continuous swimming toward \(Int(target)) m."
        case .cyclingEndurance(let minutes):
            "Build cycling endurance beyond the current \(minutes)-minute capability."
        case .cyclingDistance(let current, let target):
            current > 0
                ? "Build riding distance from \(formatDistance(current)) toward \(formatDistance(target))."
                : "Build recorded riding distance toward \(formatDistance(target))."
        case .brickExperience:
            "Add bike-to-run transition practice."
        case .trainingConsistency:
            "Re-establish consistent training before adding event-specific demand."
        case .insufficientRecentEvidence:
            "Complete and report more sessions to improve readiness confidence."
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1_000
            ? String(format: "%.1f km", meters / 1_000)
            : "\(Int(meters.rounded())) m"
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

enum TrainingJourneyReason: String, Codable, Equatable, Sendable {
    case swimGap
    case runContinuityGap
    case runEnduranceGap
    case cyclingEnduranceGap
    case raceSpecificPhase
    case taperPhase
    case recoveryOverride
    case brickPreparation
    case insufficientEvidence
    case consistency
    case eventOutcomePending
    case nextObjectiveRequired
}

struct WeeklyTrainingObjective: Equatable, Sendable, Identifiable {
    var sport: Sport?
    var kind: WeeklyTrainingObjectiveKind
    var priority: Int
    var reason: TrainingJourneyReason = .consistency
    var id: String { "\(sport?.rawValue ?? "all")-\(kind.rawValue)-\(priority)" }
}

struct SportPriority: Equatable, Sendable, Identifiable {
    var sport: Sport
    var rank: Int
    var reason: String
    var reasonCode: TrainingJourneyReason = .consistency
    var id: Sport { sport }
}

struct TrainingJourney: Equatable, Sendable {
    var phase: TrainingPhase
    var weeksRemaining: Int?
    var readiness: EventReadiness
    var weeklyObjectives: [WeeklyTrainingObjective]
    var sportPriorities: [SportPriority]
    var eventResolutionRequired: Bool = false
    var requiresNextObjective: Bool = false
    var recoveryDaysRemaining: Int? = nil

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

    var recoveryPolicy = EventRecoveryPolicy()

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

    func phase(
        for event: AthleteEventGoal,
        capability: AthleteCapabilityAssessment,
        eventState: AthleteEventState,
        asOf date: Date,
        calendar: Calendar
    ) -> TrainingPhase {
        if eventState.status == .completed {
            if recoveryPolicy.isRecovering(event: event, state: eventState, asOf: date, calendar: calendar) {
                return .recovery
            }
            return .foundation
        }

        if eventState.status == .missed || eventState.status == .cancelled {
            return .foundation
        }

        guard let days = event.daysRemaining(asOf: date, calendar: calendar) else {
            return needsFoundation(event: event, capability: capability) ? .foundation : .build
        }

        // A passed date with no outcome is deliberately *not* interpreted as a
        // completion. Keep load light until the athlete resolves what happened.
        if days < 0 { return .raceWeek }
        if days <= 7 { return .raceWeek }

        let weeks = event.weeksRemaining(asOf: date, calendar: calendar) ?? 0
        let rules = thresholds(for: event)
        if weeks <= rules.taperStartsAtWeeksRemaining { return .taper }
        if weeks <= rules.specificStartsAtWeeksRemaining { return .specific }

        if needsFoundation(event: event, capability: capability) { return .foundation }
        return .build
    }

    private func needsFoundation(
        event: AthleteEventGoal,
        capability: AthleteCapabilityAssessment
    ) -> Bool {
        switch event.sport {
        case .running:
            !capability.running.hasContinuousCapability
        case .swimming:
            (capability.swimming.currentContinuousMeters ?? 0)
                < min(event.distance?.components.swimMeters ?? 200, 200)
        case .cycling:
            capability.cycling.currentComfortableSeconds < 30 * 60
        case .triathlon:
            !capability.running.hasContinuousCapability
                || (capability.swimming.currentContinuousMeters ?? 0) < 100
                || capability.cycling.currentComfortableSeconds < 30 * 60
        }
    }
}

struct TrainingJourneyPlanner: Sendable {
    var policy = TrainingJourneyPolicy()
    var capabilityBuilder = AthleteCapabilityAssessmentBuilder()
    var calendar: Calendar = .current

    func plan(
        setup: AthleteSetup,
        plans: [WeeklyPlan],
        asOf date: Date = .now
    ) -> TrainingJourney {
        let capability = capabilityBuilder.build(setup: setup, plans: plans, asOf: date)
        return plan(setup: setup, capability: capability, asOf: date)
    }

    /// Compatibility entry point used by older callers. All interpretation
    /// still goes through the shared capability assessment.
    func plan(
        setup: AthleteSetup,
        recentPlans: [WeeklyPlan] = [],
        asOf date: Date = .now
    ) -> TrainingJourney {
        plan(setup: setup, plans: recentPlans, asOf: date)
    }

    func plan(
        setup: AthleteSetup,
        capability: AthleteCapabilityAssessment,
        asOf date: Date = .now
    ) -> TrainingJourney {
        guard setup.objective.kind == .event, let event = setup.objective.event else {
            return generalJourney(setup: setup, capability: capability)
        }

        let phase = policy.phase(
            for: event,
            capability: capability,
            eventState: setup.eventState,
            asOf: date,
            calendar: calendar
        )
        let readiness = readiness(for: event, capability: capability, asOf: date)
        let priorities = priorities(for: event, capability: capability)
        let objectives = objectives(
            for: event,
            capability: capability,
            phase: phase,
            priorities: priorities
        )
        let passedUnresolved = (event.daysRemaining(asOf: date, calendar: calendar) ?? 0) < 0
            && setup.eventState.status == .upcoming
        let needsNext = (setup.eventState.status == .completed
            && phase != .recovery)
            || setup.eventState.status == .missed
            || setup.eventState.status == .cancelled

        return TrainingJourney(
            phase: phase,
            weeksRemaining: event.weeksRemaining(asOf: date, calendar: calendar),
            readiness: readiness,
            weeklyObjectives: needsNext
                ? [.init(sport: nil, kind: .consistency, priority: 1, reason: .nextObjectiveRequired)]
                : objectives,
            sportPriorities: priorities,
            eventResolutionRequired: passedUnresolved,
            requiresNextObjective: needsNext,
            recoveryDaysRemaining: phase == .recovery
                ? policy.recoveryPolicy.daysRemaining(
                    event: event,
                    state: setup.eventState,
                    asOf: date,
                    calendar: calendar
                )
                : nil
        )
    }

    private func generalJourney(
        setup: AthleteSetup,
        capability: AthleteCapabilityAssessment
    ) -> TrainingJourney {
        let sports = setup.selectedSports
        let priorities = sports.enumerated().map {
            SportPriority(
                sport: $0.element,
                rank: $0.offset + 1,
                reason: generalReason(for: $0.element, capability: capability),
                reasonCode: .consistency
            )
        }
        return TrainingJourney(
            phase: .foundation,
            weeksRemaining: nil,
            readiness: EventReadiness(status: .notEnoughData, sports: []),
            weeklyObjectives: [.init(sport: nil, kind: .consistency, priority: 1, reason: .consistency)],
            sportPriorities: priorities
        )
    }

    private func generalReason(
        for sport: Sport,
        capability: AthleteCapabilityAssessment
    ) -> String {
        switch sport {
        case .running:
            capability.running.recentDirection == .building
                ? "Running continuity is building."
                : "Build sustainable running consistency."
        case .swimming:
            capability.swimming.recentDirection == .building
                ? "Swimming continuity is building."
                : "Build sustainable swimming consistency."
        case .cycling:
            capability.cycling.recentDirection == .building
                ? "Cycling endurance is building."
                : "Build sustainable cycling consistency."
        }
    }

    private func readiness(
        for event: AthleteEventGoal,
        capability: AthleteCapabilityAssessment,
        asOf date: Date
    ) -> EventReadiness {
        let sports = event.sport.requiredTrainingSports.map { sport -> SportReadiness in
            let gaps = gaps(for: sport, event: event, capability: capability)
            let status: EventReadinessStatus
            if !capability.hasRecentTrainingEvidence {
                status = .notEnoughData
            } else if capability.recoveryState != .stable {
                status = .needsAttention
            } else if gaps.isEmpty {
                status = .onTrack
            } else {
                status = .building
            }
            return SportReadiness(sport: sport, status: status, gaps: gaps)
        }

        guard capability.hasRecentTrainingEvidence else {
            return EventReadiness(
                status: .notEnoughData,
                sports: sports.map {
                    var value = $0
                    if !value.gaps.contains(.insufficientRecentEvidence) {
                        value.gaps.append(.insufficientRecentEvidence)
                    }
                    value.status = .notEnoughData
                    return value
                }
            )
        }

        if capability.recoveryState != .stable {
            return EventReadiness(status: .needsAttention, sports: sports)
        }

        let adherence = capability.recentAdherence ?? 0
        let consistencyThreat = capability.recentMissedOrSkippedSessions >= 3 && adherence < 0.5
        let weeks = event.weeksRemaining(asOf: date, calendar: calendar)
        let majorGapNearEvent = (weeks ?? Int.max) <= 2
            && event.sport.requiredTrainingSports.contains {
                capabilityRatio(for: $0, event: event, capability: capability) < 0.5
            }

        if consistencyThreat || majorGapNearEvent {
            return EventReadiness(status: .needsAttention, sports: sports)
        }

        if isEventReady(event: event, capability: capability) {
            return EventReadiness(status: .eventReady, sports: sports)
        }

        let ratios = event.sport.requiredTrainingSports.map {
            capabilityRatio(for: $0, event: event, capability: capability)
        }
        let hasSufficientPreparation = capability.recentCompletedSessions >= 3
            && adherence >= 0.6
            && ratios.allSatisfy { $0 >= 0.6 }

        return EventReadiness(
            status: hasSufficientPreparation ? .onTrack : .building,
            sports: sports
        )
    }

    private func gaps(
        for sport: Sport,
        event: AthleteEventGoal,
        capability: AthleteCapabilityAssessment
    ) -> [ReadinessGap] {
        var result: [ReadinessGap] = []

        switch sport {
        case .running:
            if !capability.running.hasContinuousCapability {
                result.append(.runningContinuity)
            }
            let target = event.distance?.components.runMeters ?? 0
            if target > 0, capability.running.recentBestDistanceMeters < target {
                result.append(.runningEndurance)
            }

        case .swimming:
            let current = capability.swimming.recentLongestProvenContinuousMeters ?? 0
            let target = event.distance?.components.swimMeters ?? 0
            if target > 0, current < target {
                result.append(.swimContinuity(currentMeters: current, targetMeters: target))
            }

        case .cycling:
            let target = event.distance?.components.bikeMeters ?? 0
            if target > 0 {
                if capability.cycling.recentBestDistanceMeters < target {
                    result.append(.cyclingDistance(
                        currentMeters: capability.cycling.recentBestDistanceMeters,
                        targetMeters: target
                    ))
                }
            } else if capability.cycling.currentComfortableSeconds < 45 * 60 {
                result.append(.cyclingEndurance(
                    currentMinutes: Int(capability.cycling.currentComfortableSeconds / 60)
                ))
            }
        }

        if event.sport == .triathlon,
           sport == .cycling,
           capability.completedBrickCount == 0 {
            result.append(.brickExperience)
        }

        return result
    }

    private func isEventReady(
        event: AthleteEventGoal,
        capability: AthleteCapabilityAssessment
    ) -> Bool {
        guard capability.recoveryState == .stable,
              capability.recentCompletedSessions >= 4,
              (capability.recentAdherence ?? 0) >= 0.7 else {
            return false
        }

        for sport in event.sport.requiredTrainingSports {
            guard capability.hasRecentDemonstratedEvidence(for: sport),
                  capabilityRatio(for: sport, event: event, capability: capability) >= 1 else {
                return false
            }
        }

        if event.sport == .triathlon, capability.completedBrickCount == 0 {
            return false
        }
        return true
    }

    private func capabilityRatio(
        for sport: Sport,
        event: AthleteEventGoal,
        capability: AthleteCapabilityAssessment
    ) -> Double {
        let target: Double
        let current: Double
        switch sport {
        case .running:
            target = event.distance?.components.runMeters ?? 0
            current = capability.running.recentBestDistanceMeters
        case .swimming:
            target = event.distance?.components.swimMeters ?? 0
            current = capability.swimming.recentLongestProvenContinuousMeters ?? 0
        case .cycling:
            target = event.distance?.components.bikeMeters ?? 0
            current = capability.cycling.recentBestDistanceMeters
        }

        guard target > 0 else {
            return capability.hasRecentDemonstratedEvidence(for: sport) ? 1 : 0
        }
        return min(max(current / target, 0), 1)
    }

    private func priorities(
        for event: AthleteEventGoal,
        capability: AthleteCapabilityAssessment
    ) -> [SportPriority] {
        let scored = event.sport.requiredTrainingSports.map { sport -> (Sport, Double, String, TrainingJourneyReason) in
            switch sport {
            case .running:
                if !capability.running.hasContinuousCapability {
                    return (.running, 4, "Running continuity is the largest current gap.", .runContinuityGap)
                }
                let ratio = capabilityRatio(for: .running, event: event, capability: capability)
                return (
                    .running,
                    3 * (1 - ratio),
                    ratio < 1 ? "Build running endurance toward the event." : "Maintain demonstrated running capability.",
                    .runEnduranceGap
                )

            case .swimming:
                let ratio = capabilityRatio(for: .swimming, event: event, capability: capability)
                return (
                    .swimming,
                    4 * (1 - ratio),
                    ratio < 1 ? "Swimming continuity is the largest current gap." : "Maintain demonstrated swim continuity.",
                    .swimGap
                )

            case .cycling:
                let ratio = capabilityRatio(for: .cycling, event: event, capability: capability)
                let durationGap = capability.cycling.currentComfortableSeconds < 30 * 60 ? 1.0 : 0
                return (
                    .cycling,
                    max(3 * (1 - ratio), durationGap),
                    ratio < 1 ? "Build cycling endurance toward the event." : "Maintain demonstrated cycling capability.",
                    .cyclingEnduranceGap
                )
            }
        }

        return scored
            .sorted {
                if $0.1 == $1.1 { return $0.0.rawValue < $1.0.rawValue }
                return $0.1 > $1.1
            }
            .enumerated()
            .map {
                SportPriority(
                    sport: $0.element.0,
                    rank: $0.offset + 1,
                    reason: $0.element.2,
                    reasonCode: $0.element.3
                )
            }
    }

    private func objectives(
        for event: AthleteEventGoal,
        capability: AthleteCapabilityAssessment,
        phase: TrainingPhase,
        priorities: [SportPriority]
    ) -> [WeeklyTrainingObjective] {
        if phase == .recovery {
            return [.init(sport: nil, kind: .recovery, priority: 1, reason: .recoveryOverride)]
        }
        if phase == .taper || phase == .raceWeek {
            return [.init(sport: nil, kind: .taper, priority: 1, reason: .taperPhase)]
        }

        var objectives = priorities.map { priority in
            let kind: WeeklyTrainingObjectiveKind
            let reason: TrainingJourneyReason
            switch priority.sport {
            case .running:
                if !capability.running.hasContinuousCapability {
                    kind = .runWalkContinuity
                    reason = .runContinuityGap
                } else {
                    kind = phase == .specific ? .racePacing : .endurance
                    reason = phase == .specific ? .raceSpecificPhase : .runEnduranceGap
                }
            case .swimming:
                let target = event.distance?.components.swimMeters ?? 200
                if (capability.swimming.currentContinuousMeters ?? 0) < target {
                    kind = .swimContinuity
                    reason = .swimGap
                } else {
                    kind = .swimTechnique
                    reason = phase == .specific ? .raceSpecificPhase : .swimGap
                }
            case .cycling:
                kind = phase == .specific ? .racePacing : .endurance
                reason = phase == .specific ? .raceSpecificPhase : .cyclingEnduranceGap
            }
            return WeeklyTrainingObjective(
                sport: priority.sport,
                kind: kind,
                priority: priority.rank,
                reason: reason
            )
        }

        if event.sport == .triathlon, phase == .specific {
            objectives.append(
                WeeklyTrainingObjective(
                    sport: nil,
                    kind: .brickTransition,
                    priority: priorities.count + 1,
                    reason: .brickPreparation
                )
            )
        }
        return objectives
    }
}
