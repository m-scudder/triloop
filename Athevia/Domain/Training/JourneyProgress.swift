import Foundation

enum JourneyMilestoneKind: String, Codable, Sendable {
    // Running
    case firstRun
    case firstContinuousRun
    case run10MinutesContinuous
    case run20MinutesContinuous
    case run30MinutesContinuous
    case firstFiveK
    case first10K
    case firstHalfMarathon
    case longestRun

    // Cycling
    case firstRide
    case ride30Minutes
    case ride60Minutes
    case first20KRide
    case first50KRide
    case first100KRide
    case longestRide

    // Swimming
    case firstSwim
    case firstPoolLength
    case swim100Continuous
    case swim250Continuous
    case swim500Continuous
    case swim1KContinuous
    case firstOpenWaterSwim
    case longestContinuousSwim
    case longestTotalSwimWorkout

    // Multisport
    case firstBrick
    case firstTransitionPractice
    case firstMultisportWorkout
    case firstSuperSprint
    case firstSprint
    case firstOlympic
    case first703

    // Consistency / lifecycle
    case firstCompleteTrainingWeek
    case threeConsistentWeeks
    case tenCompletedPlannedSessions
    case consistency
    case eventWeek
    case eventCompleted

    var displayName: String {
        switch self {
        case .firstRun: "First completed run"
        case .firstContinuousRun: "First continuous run"
        case .run10MinutesContinuous: "10 min continuous run"
        case .run20MinutesContinuous: "20 min continuous run"
        case .run30MinutesContinuous: "30 min continuous run"
        case .firstFiveK: "First 5K"
        case .first10K: "First 10K"
        case .firstHalfMarathon: "First Half Marathon"
        case .longestRun: "Longest run"
        case .firstRide: "First ride"
        case .ride30Minutes: "First 30 min ride"
        case .ride60Minutes: "First 60 min ride"
        case .first20KRide: "First 20K ride"
        case .first50KRide: "First 50K ride"
        case .first100KRide: "First 100K ride"
        case .longestRide: "Longest ride"
        case .firstSwim: "First swim"
        case .firstPoolLength: "First full pool length"
        case .swim100Continuous: "100 m continuous swim"
        case .swim250Continuous: "250 m continuous swim"
        case .swim500Continuous: "500 m continuous swim"
        case .swim1KContinuous: "1 km continuous swim"
        case .firstOpenWaterSwim: "First open-water swim"
        case .longestContinuousSwim: "Longest continuous swim"
        case .longestTotalSwimWorkout: "Longest total swim workout"
        case .firstBrick: "First brick"
        case .firstTransitionPractice: "First transition practice"
        case .firstMultisportWorkout: "First multisport workout"
        case .firstSuperSprint: "First Super Sprint"
        case .firstSprint: "First Sprint Triathlon"
        case .firstOlympic: "First Olympic Triathlon"
        case .first703: "First 70.3"
        case .firstCompleteTrainingWeek: "First complete training week"
        case .threeConsistentWeeks, .consistency: "3 consistent weeks"
        case .tenCompletedPlannedSessions: "10 planned sessions completed"
        case .eventWeek: "Event week reached"
        case .eventCompleted: "Event completed"
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
    var capabilityBuilder = AthleteCapabilityAssessmentBuilder()

    func build(
        setup: AthleteSetup,
        plans: [WeeklyPlan],
        asOf date: Date = .now
    ) -> JourneyProgressSnapshot {
        let capability = capabilityBuilder.build(setup: setup, plans: plans, asOf: date)
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: setup, capability: capability, asOf: date)

        return JourneyProgressSnapshot(
            journey: journey,
            capabilities: capabilities(setup: setup, capability: capability),
            milestones: milestones(setup: setup, plans: plans, asOf: date),
            nextAction: nextAction(for: journey)
        )
    }

    private func capabilities(
        setup: AthleteSetup,
        capability: AthleteCapabilityAssessment
    ) -> [CapabilityRequirement] {
        guard let event = setup.objective.event else { return [] }

        return event.sport.requiredTrainingSports.map { sport in
            switch sport {
            case .running:
                let target = event.distance?.components.runMeters ?? 0
                let demonstrated = capability.running.longestRecordedDistanceMeters
                let evidence: String
                if demonstrated > 0 {
                    if let baseline = capability.running.reportedDistanceMeters {
                        evidence = "\(distance(demonstrated)) recorded · baseline \(distance(baseline))"
                    } else {
                        evidence = "\(distance(demonstrated)) recorded"
                    }
                } else if let baseline = capability.running.reportedDistanceMeters {
                    evidence = "\(distance(baseline)) onboarding baseline"
                } else if let seconds = capability.running.demonstratedContinuousSeconds {
                    evidence = "\(minutes(seconds)) continuous demonstrated"
                } else if let seconds = capability.running.prescribedContinuousSeconds {
                    evidence = "\(minutes(seconds)) continuous prescribed"
                } else if capability.running.reportedContinuousSeconds != nil {
                    evidence = "Continuous running reported"
                } else {
                    evidence = "No distance baseline yet"
                }
                return CapabilityRequirement(
                    sport: .running,
                    requirement: target > 0 ? "\(distance(target)) run" : "Continuous running",
                    currentEvidence: evidence,
                    state: target > 0 && demonstrated >= target
                        ? .demonstrated
                        : (capability.running.hasDemonstratedCapability ? .developing : .notEnoughData)
                )

            case .swimming:
                let target = event.distance?.components.swimMeters ?? 0
                let proven = capability.swimming.longestProvenContinuousMeters ?? 0
                let evidence: String
                if proven > 0 {
                    if let baseline = capability.swimming.reportedContinuousMeters {
                        evidence = "\(distance(proven)) continuous recorded · baseline \(distance(baseline))"
                    } else {
                        evidence = "\(distance(proven)) continuous recorded"
                    }
                } else if capability.swimming.longestRecordedTotalWorkoutMeters > 0 {
                    evidence = "\(distance(capability.swimming.longestRecordedTotalWorkoutMeters)) total recorded · Continuous distance not verified"
                } else if let reported = capability.swimming.reportedContinuousMeters {
                    evidence = "\(distance(reported)) continuous reported"
                } else {
                    evidence = "Continuous distance not verified"
                }
                return CapabilityRequirement(
                    sport: .swimming,
                    requirement: target > 0 ? "\(distance(target)) continuous swim" : "Continuous swimming",
                    currentEvidence: evidence,
                    state: target > 0 && proven >= target
                        ? .demonstrated
                        : (capability.swimming.hasDemonstratedCapability ? .developing : .notEnoughData)
                )

            case .cycling:
                let target = event.distance?.components.bikeMeters ?? 0
                let demonstrated = capability.cycling.longestRecordedDistanceMeters
                let evidence: String
                if demonstrated > 0 {
                    evidence = "\(distance(demonstrated)) recorded · baseline \(distance(capability.cycling.reportedDistanceMeters))"
                } else if capability.cycling.bestRecentDurationSeconds > 0 {
                    evidence = "\(minutes(capability.cycling.bestRecentDurationSeconds)) recorded · baseline \(distance(capability.cycling.reportedDistanceMeters))"
                } else {
                    evidence = "\(distance(capability.cycling.reportedDistanceMeters)) onboarding baseline"
                }
                return CapabilityRequirement(
                    sport: .cycling,
                    requirement: target > 0 ? "\(distance(target)) ride" : "Endurance riding",
                    currentEvidence: evidence,
                    state: target > 0 && demonstrated >= target
                        ? .demonstrated
                        : (capability.cycling.hasDemonstratedCapability ? .developing : .notEnoughData)
                )
            }
        }
    }

    func milestones(
        setup: AthleteSetup,
        plans: [WeeklyPlan],
        asOf date: Date
    ) -> [JourneyMilestone] {
        let completed = plans
            .flatMap(\.trainingSessions)
            .filter(\.isCompleted)
            .sorted { achievedDate($0) < achievedDate($1) }
        var result: [JourneyMilestone] = []

        if let first = firstSportEvidence(.running, in: completed) {
            result.append(.init(kind: .firstRun, achievedAt: first, detail: "Running recorded"))
        }

        if let first = firstSportEvidence(.cycling, in: completed) {
            result.append(.init(kind: .firstRide, achievedAt: first, detail: "Cycling recorded"))
        }

        if let first = firstSportEvidence(.swimming, in: completed) {
            result.append(.init(kind: .firstSwim, achievedAt: first, detail: "Swimming recorded"))
        }

        addRunContinuityMilestones(plans: plans, into: &result)
        addDistanceMilestones(completed: completed, into: &result)
        addRideDurationMilestones(completed: completed, into: &result)
        addSwimMilestones(completed: completed, into: &result)
        addMultisportMilestones(completed: completed, setup: setup, into: &result)
        addConsistencyMilestones(plans: plans, into: &result)

        if let event = setup.objective.event, let eventDate = event.eventDate {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: eventDate)
            ).day ?? 0
            if setup.eventState.status == .upcoming, (0...7).contains(days) {
                result.append(.init(kind: .eventWeek, achievedAt: date, detail: "Event week"))
            }
        }

        if setup.eventState.status == .completed, let event = setup.objective.event {
            let completedAt = setup.eventState.resolvedAt ?? event.eventDate ?? date
            result.append(.init(
                kind: .eventCompleted,
                achievedAt: completedAt,
                detail: event.displayName
            ))
        }

        return deduplicated(result).sorted { $0.achievedAt < $1.achievedAt }
    }


    private func firstSportEvidence(
        _ sport: Sport,
        in completed: [PlannedWorkout]
    ) -> Date? {
        completed.compactMap { workout -> Date? in
            if workout.discipline.sport == sport {
                return achievedDate(workout)
            }
            let hasSegment = (workout.importedSummary?.metrics?.multisportSegments ?? [])
                .contains { $0.sport == sport && $0.durationSeconds > 0 }
            return hasSegment ? achievedDate(workout) : nil
        }.min()
    }

    private func addRunContinuityMilestones(
        plans: [WeeklyPlan],
        into result: inout [JourneyMilestone]
    ) {
        var evidence: [(Date, TimeInterval)] = []
        for plan in plans {
            guard plan.parameters.runIsContinuous else { continue }
            for workout in plan.trainingSessions where workout.discipline == .running && workout.isCompleted {
                evidence.append((
                    achievedDate(workout),
                    plan.parameters.runContinuousSeconds * workout.recordedCompletion
                ))
            }
        }
        evidence.sort { $0.0 < $1.0 }
        guard !evidence.isEmpty else { return }

        if let first = evidence.first(where: { $0.1 > 0 }) {
            result.append(.init(
                kind: .firstContinuousRun,
                achievedAt: first.0,
                detail: "Continuous running completed"
            ))
        }
        addThreshold(10 * 60, kind: .run10MinutesContinuous, unit: "10 min", evidence: evidence, into: &result)
        addThreshold(20 * 60, kind: .run20MinutesContinuous, unit: "20 min", evidence: evidence, into: &result)
        addThreshold(30 * 60, kind: .run30MinutesContinuous, unit: "30 min", evidence: evidence, into: &result)
    }

    private func addThreshold(
        _ threshold: TimeInterval,
        kind: JourneyMilestoneKind,
        unit: String,
        evidence: [(Date, TimeInterval)],
        into result: inout [JourneyMilestone]
    ) {
        if let first = evidence.first(where: { $0.1 >= threshold }) {
            result.append(.init(kind: kind, achievedAt: first.0, detail: "\(unit) continuous"))
        }
    }

    private func addDistanceMilestones(
        completed: [PlannedWorkout],
        into result: inout [JourneyMilestone]
    ) {
        let runEvidence = distanceEvidence(.running, completed: completed)
        addDistanceThreshold(5_000, kind: .firstFiveK, label: "5 km", evidence: runEvidence, into: &result)
        addDistanceThreshold(10_000, kind: .first10K, label: "10 km", evidence: runEvidence, into: &result)
        addDistanceThreshold(21_097.5, kind: .firstHalfMarathon, label: "21.1 km", evidence: runEvidence, into: &result)
        if let longest = runEvidence.max(by: { $0.distance < $1.distance }), longest.distance > 0 {
            result.append(.init(
                kind: .longestRun,
                achievedAt: longest.date,
                detail: distance(longest.distance)
            ))
        }

        let rideEvidence = distanceEvidence(.cycling, completed: completed)
        addDistanceThreshold(20_000, kind: .first20KRide, label: "20 km", evidence: rideEvidence, into: &result)
        addDistanceThreshold(50_000, kind: .first50KRide, label: "50 km", evidence: rideEvidence, into: &result)
        addDistanceThreshold(100_000, kind: .first100KRide, label: "100 km", evidence: rideEvidence, into: &result)
        if let longest = rideEvidence.max(by: { $0.distance < $1.distance }), longest.distance > 0 {
            result.append(.init(
                kind: .longestRide,
                achievedAt: longest.date,
                detail: distance(longest.distance)
            ))
        }
    }

    private func addRideDurationMilestones(
        completed: [PlannedWorkout],
        into result: inout [JourneyMilestone]
    ) {
        var evidence: [(date: Date, seconds: TimeInterval)] = completed.compactMap { workout in
            guard workout.discipline == .cycling, let seconds = workout.importedSummary?.duration else {
                return nil
            }
            return (achievedDate(workout), seconds)
        }
        evidence += completed.flatMap { workout in
            (workout.importedSummary?.metrics?.multisportSegments ?? [])
                .filter { $0.sport == .cycling }
                .map { (achievedDate(workout), $0.durationSeconds) }
        }
        evidence.sort { $0.date < $1.date }

        if let first = evidence.first(where: { $0.seconds >= 30 * 60 }) {
            result.append(.init(kind: .ride30Minutes, achievedAt: first.date, detail: "30 min recorded ride"))
        }
        if let first = evidence.first(where: { $0.seconds >= 60 * 60 }) {
            result.append(.init(kind: .ride60Minutes, achievedAt: first.date, detail: "60 min recorded ride"))
        }
    }

    private func addSwimMilestones(
        completed: [PlannedWorkout],
        into result: inout [JourneyMilestone]
    ) {
        let swimSummaries = completed.compactMap { workout -> (Date, ImportedWorkoutSummary)? in
            guard workout.discipline == .swimming, let summary = workout.importedSummary else { return nil }
            return (achievedDate(workout), summary)
        }

        if let firstLength = swimSummaries.first(where: { ($0.1.swimmingLengths ?? 0) > 0 }) {
            result.append(.init(
                kind: .firstPoolLength,
                achievedAt: firstLength.0,
                detail: "Pool length recorded"
            ))
        }

        let continuous = swimSummaries.compactMap { date, summary -> (Date, Double)? in
            summary.longestContinuousSwimMeters.map { (date, $0) }
        }
        addSwimContinuousThreshold(100, kind: .swim100Continuous, evidence: continuous, into: &result)
        addSwimContinuousThreshold(250, kind: .swim250Continuous, evidence: continuous, into: &result)
        addSwimContinuousThreshold(500, kind: .swim500Continuous, evidence: continuous, into: &result)
        addSwimContinuousThreshold(1_000, kind: .swim1KContinuous, evidence: continuous, into: &result)

        if let longest = continuous.max(by: { $0.1 < $1.1 }) {
            result.append(.init(
                kind: .longestContinuousSwim,
                achievedAt: longest.0,
                detail: "\(distance(longest.1)) continuous"
            ))
        }

        var totalEvidence = swimSummaries.compactMap { date, summary -> (Date, Double)? in
            summary.distanceMeters.map { (date, $0) }
        }
        totalEvidence += completed.flatMap { workout in
            (workout.importedSummary?.metrics?.multisportSegments ?? [])
                .filter { $0.sport == .swimming }
                .compactMap { segment in segment.distanceMeters.map { (achievedDate(workout), $0) } }
        }
        if let longest = totalEvidence.max(by: { $0.1 < $1.1 }) {
            result.append(.init(
                kind: .longestTotalSwimWorkout,
                achievedAt: longest.0,
                detail: "\(distance(longest.1)) total"
            ))
        }

        let singleSportOpenWater = swimSummaries.first(where: {
            $0.1.metrics?.swimEnvironment == .openWater
        })?.0
        let multisportOpenWater = completed.compactMap { workout -> Date? in
            let hasOpenWaterSegment = (workout.importedSummary?.metrics?.multisportSegments ?? [])
                .contains {
                    $0.sport == .swimming && $0.swimEnvironment == .openWater
                }
            return hasOpenWaterSegment ? achievedDate(workout) : nil
        }.min()

        if let openWater = [singleSportOpenWater, multisportOpenWater].compactMap({ $0 }).min() {
            result.append(.init(
                kind: .firstOpenWaterSwim,
                achievedAt: openWater,
                detail: "Open-water swim recorded"
            ))
        }
    }

    private func addSwimContinuousThreshold(
        _ threshold: Double,
        kind: JourneyMilestoneKind,
        evidence: [(Date, Double)],
        into result: inout [JourneyMilestone]
    ) {
        if let first = evidence.sorted(by: { $0.0 < $1.0 }).first(where: { $0.1 >= threshold }) {
            result.append(.init(
                kind: kind,
                achievedAt: first.0,
                detail: "\(distance(threshold)) continuous"
            ))
        }
    }

    private func addMultisportMilestones(
        completed: [PlannedWorkout],
        setup: AthleteSetup,
        into result: inout [JourneyMilestone]
    ) {
        if let first = completed.first(where: \.isBrickWorkout) {
            result.append(.init(
                kind: .firstBrick,
                achievedAt: achievedDate(first),
                detail: "Bike-to-run brick completed"
            ))
        }

        if let first = completed.first(where: {
            $0.orderedSteps.contains(where: { $0.kind == .transition })
        }) {
            result.append(.init(
                kind: .firstTransitionPractice,
                achievedAt: achievedDate(first),
                detail: "Transition segment completed"
            ))
        }

        if let first = completed.first(where: { $0.discipline == .multisport }) {
            result.append(.init(
                kind: .firstMultisportWorkout,
                achievedAt: achievedDate(first),
                detail: first.title
            ))
        }

        guard setup.eventState.status == .completed,
              let event = setup.objective.event,
              event.sport == .triathlon else { return }
        let achievedAt = setup.eventState.resolvedAt ?? event.eventDate ?? .now
        let kind: JourneyMilestoneKind? = switch event.distance?.kind {
        case .triathlonSuperSprint: .firstSuperSprint
        case .triathlonSprint: .firstSprint
        case .triathlonOlympic: .firstOlympic
        case .triathlon703: .first703
        default: nil
        }
        if let kind {
            result.append(.init(kind: kind, achievedAt: achievedAt, detail: event.displayName))
        }
    }

    private func addConsistencyMilestones(
        plans: [WeeklyPlan],
        into result: inout [JourneyMilestone]
    ) {
        let ordered = plans.sorted { $0.startDate < $1.startDate }
        let completeWeeks = ordered.filter { plan in
            let prescribed = plan.prescribedTrainingSessions
            return !prescribed.isEmpty && prescribed.allSatisfy(\.isCompleted)
        }
        if let first = completeWeeks.first {
            result.append(.init(
                kind: .firstCompleteTrainingWeek,
                achievedAt: first.endDate,
                detail: "All planned training sessions completed"
            ))
        }

        let consistent = ordered.filter { plan in
            let prescribed = plan.prescribedTrainingSessions
            guard !prescribed.isEmpty else { return false }
            return Double(prescribed.filter(\.isCompleted).count) / Double(prescribed.count) >= 0.8
        }
        if consistent.count >= 3 {
            let third = consistent[2]
            result.append(.init(
                kind: .threeConsistentWeeks,
                achievedAt: third.endDate,
                detail: "Three training weeks completed consistently"
            ))
        }

        let prescribedCompleted = ordered
            .flatMap(\.prescribedTrainingSessions)
            .filter(\.isCompleted)
            .sorted { achievedDate($0) < achievedDate($1) }
        if prescribedCompleted.count >= 10 {
            let tenth = prescribedCompleted[9]
            result.append(.init(
                kind: .tenCompletedPlannedSessions,
                achievedAt: achievedDate(tenth),
                detail: "10 planned sessions completed"
            ))
        }
    }

    private func distanceEvidence(
        _ sport: Sport,
        completed: [PlannedWorkout]
    ) -> [(date: Date, distance: Double)] {
        var evidence = completed.compactMap { workout -> (date: Date, distance: Double)? in
            guard workout.discipline.sport == sport,
                  let value = workout.importedSummary?.distanceMeters else { return nil }
            return (date: achievedDate(workout), distance: value)
        }
        evidence += completed.flatMap { workout in
            (workout.importedSummary?.metrics?.multisportSegments ?? [])
                .filter { $0.sport == sport }
                .compactMap { segment in
                    segment.distanceMeters.map {
                        (date: achievedDate(workout), distance: $0)
                    }
                }
        }
        return evidence.sorted { $0.date < $1.date }
    }

    private func addDistanceThreshold(
        _ threshold: Double,
        kind: JourneyMilestoneKind,
        label: String,
        evidence: [(date: Date, distance: Double)],
        into result: inout [JourneyMilestone]
    ) {
        if let first = evidence.first(where: { $0.distance >= threshold }) {
            result.append(.init(kind: kind, achievedAt: first.date, detail: "\(label) recorded"))
        }
    }

    private func deduplicated(_ milestones: [JourneyMilestone]) -> [JourneyMilestone] {
        var seen: Set<JourneyMilestoneKind> = []
        return milestones
            .sorted { $0.achievedAt < $1.achievedAt }
            .filter { seen.insert($0.kind).inserted }
    }

    private func nextAction(for journey: TrainingJourney) -> String {
        if journey.eventResolutionRequired {
            return "Tell Athevia what happened with your event before the next training block."
        }
        if journey.requiresNextObjective {
            return "Choose what you want to train toward next."
        }
        if journey.phase == .recovery {
            if let days = journey.recoveryDaysRemaining, days > 0 {
                return "Keep recovery easy for about \(days) more day\(days == 1 ? "" : "s")."
            }
            return "Choose what you want to train toward next."
        }
        if journey.phase == .raceWeek {
            return "Keep training light and follow the race-week plan."
        }
        if let gap = journey.readiness.sports.flatMap(\.gaps).first(where: { $0 != .insufficientRecentEvidence }) {
            return gap.message
        }
        if let focus = journey.primaryFocus { return focus.kind.displayName + "." }
        return "Complete and report the next prescribed session."
    }

    private func achievedDate(_ workout: PlannedWorkout) -> Date {
        workout.completedAt ?? workout.importedSummary?.endDate ?? workout.date
    }

    private func distance(_ meters: Double) -> String {
        meters >= 1_000
            ? String(format: "%.1f km", meters / 1_000)
            : "\(Int(meters.rounded())) m"
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }
}
