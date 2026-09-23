import Foundation

/// The layer above Athevia's existing adaptive engine: what the athlete is
/// ultimately training toward. This stays deterministic and stores structured
/// event facts rather than display strings.
enum TrainingObjectiveKind: String, Codable, CaseIterable, Sendable {
    case generalFitness
    case improveEndurance
    case returnToTraining
    case event

    var displayName: String {
        switch self {
        case .generalFitness: "General Fitness"
        case .improveEndurance: "Improve Endurance"
        case .returnToTraining: "Return to Training"
        case .event: "Event / First Race"
        }
    }

    var detail: String {
        switch self {
        case .generalFitness: "Build a sustainable mix of training."
        case .improveEndurance: "Go further and for longer without a fixed event."
        case .returnToTraining: "Rebuild steadily after time away."
        case .event: "Prepare toward a specific run, swim, ride or triathlon."
        }
    }
}

enum EventSport: String, Codable, CaseIterable, Sendable {
    case running
    case swimming
    case cycling
    case triathlon

    var displayName: String {
        switch self {
        case .running: "Run"
        case .swimming: "Swim"
        case .cycling: "Cycle"
        case .triathlon: "Triathlon"
        }
    }

    var requiredTrainingSports: [Sport] {
        switch self {
        case .running: [.running]
        case .swimming: [.swimming]
        case .cycling: [.cycling]
        case .triathlon: [.swimming, .cycling, .running]
        }
    }

    init?(trainingSport: Sport) {
        switch trainingSport {
        case .running: self = .running
        case .swimming: self = .swimming
        case .cycling: self = .cycling
        }
    }
}

enum EventTargetIntent: String, Codable, CaseIterable, Sendable {
    case finishComfortably
    case complete
    case performance

    var displayName: String {
        switch self {
        case .finishComfortably: "Finish comfortably"
        case .complete: "Complete"
        case .performance: "Performance"
        }
    }
}

/// Stable domain identifiers for supported event distances.
///
/// Labels are presentation only. EventDistance also stores the actual
/// component distances so future journey logic never has to parse these names.
enum EventDistanceKind: String, Codable, CaseIterable, Sendable {
    case run5K
    case run10K
    case runHalfMarathon
    case runMarathon
    case runCustom

    case cycling20K
    case cycling50K
    case cycling100K
    case cyclingCustom

    case swimming500M
    case swimming1K
    case swimming2K
    case swimmingCustom

    case triathlonSuperSprint
    case triathlonSprint
    case triathlonOlympic
    case triathlon703
    case triathlonCustom

    var sport: EventSport {
        switch self {
        case .run5K, .run10K, .runHalfMarathon, .runMarathon, .runCustom:
            .running
        case .cycling20K, .cycling50K, .cycling100K, .cyclingCustom:
            .cycling
        case .swimming500M, .swimming1K, .swimming2K, .swimmingCustom:
            .swimming
        case .triathlonSuperSprint, .triathlonSprint, .triathlonOlympic, .triathlon703, .triathlonCustom:
            .triathlon
        }
    }

    var displayName: String {
        switch self {
        case .run5K: "5K"
        case .run10K: "10K"
        case .runHalfMarathon: "Half Marathon"
        case .runMarathon: "Marathon"
        case .runCustom: "Custom"
        case .cycling20K: "20K"
        case .cycling50K: "50K"
        case .cycling100K: "100K"
        case .cyclingCustom: "Custom"
        case .swimming500M: "500 m"
        case .swimming1K: "1 km"
        case .swimming2K: "2 km"
        case .swimmingCustom: "Custom"
        case .triathlonSuperSprint: "Super Sprint"
        case .triathlonSprint: "Sprint"
        case .triathlonOlympic: "Olympic"
        case .triathlon703: "70.3"
        case .triathlonCustom: "Custom"
        }
    }

    var isCustom: Bool {
        switch self {
        case .runCustom, .cyclingCustom, .swimmingCustom, .triathlonCustom: true
        default: false
        }
    }

    static func choices(for sport: EventSport) -> [EventDistanceKind] {
        allCases.filter { $0.sport == sport }
    }
}

struct EventDistanceComponents: Codable, Equatable, Sendable {
    var swimMeters: Double?
    var bikeMeters: Double?
    var runMeters: Double?

    init(swimMeters: Double? = nil, bikeMeters: Double? = nil, runMeters: Double? = nil) {
        self.swimMeters = swimMeters
        self.bikeMeters = bikeMeters
        self.runMeters = runMeters
    }

    func isValid(for sport: EventSport) -> Bool {
        func positive(_ value: Double?) -> Bool {
            guard let value else { return false }
            return value.isFinite && value > 0
        }

        switch sport {
        case .running:
            return positive(runMeters)
        case .swimming:
            return positive(swimMeters)
        case .cycling:
            return positive(bikeMeters)
        case .triathlon:
            return positive(swimMeters) && positive(bikeMeters) && positive(runMeters)
        }
    }
}

struct EventDistance: Codable, Equatable, Sendable {
    var kind: EventDistanceKind
    var components: EventDistanceComponents

    init(kind: EventDistanceKind, components: EventDistanceComponents? = nil) {
        self.kind = kind
        self.components = components ?? Self.defaultComponents(for: kind)
    }

    static func defaultForSport(_ sport: EventSport) -> EventDistance {
        switch sport {
        case .running: EventDistance(kind: .run5K)
        case .swimming: EventDistance(kind: .swimming500M)
        case .cycling: EventDistance(kind: .cycling20K)
        case .triathlon: EventDistance(kind: .triathlonSprint)
        }
    }

    static func custom(
        for sport: EventSport,
        swimMeters: Double? = nil,
        bikeMeters: Double? = nil,
        runMeters: Double? = nil
    ) -> EventDistance {
        let kind: EventDistanceKind = switch sport {
        case .running: .runCustom
        case .swimming: .swimmingCustom
        case .cycling: .cyclingCustom
        case .triathlon: .triathlonCustom
        }
        return EventDistance(
            kind: kind,
            components: EventDistanceComponents(
                swimMeters: swimMeters,
                bikeMeters: bikeMeters,
                runMeters: runMeters
            )
        )
    }

    private static func defaultComponents(for kind: EventDistanceKind) -> EventDistanceComponents {
        switch kind {
        case .run5K:
            EventDistanceComponents(runMeters: 5_000)
        case .run10K:
            EventDistanceComponents(runMeters: 10_000)
        case .runHalfMarathon:
            EventDistanceComponents(runMeters: 21_097.5)
        case .runMarathon:
            EventDistanceComponents(runMeters: 42_195)
        case .runCustom:
            EventDistanceComponents(runMeters: 5_000)

        case .cycling20K:
            EventDistanceComponents(bikeMeters: 20_000)
        case .cycling50K:
            EventDistanceComponents(bikeMeters: 50_000)
        case .cycling100K:
            EventDistanceComponents(bikeMeters: 100_000)
        case .cyclingCustom:
            EventDistanceComponents(bikeMeters: 20_000)

        case .swimming500M:
            EventDistanceComponents(swimMeters: 500)
        case .swimming1K:
            EventDistanceComponents(swimMeters: 1_000)
        case .swimming2K:
            EventDistanceComponents(swimMeters: 2_000)
        case .swimmingCustom:
            EventDistanceComponents(swimMeters: 500)

        case .triathlonSuperSprint:
            EventDistanceComponents(swimMeters: 400, bikeMeters: 10_000, runMeters: 2_500)
        case .triathlonSprint:
            EventDistanceComponents(swimMeters: 750, bikeMeters: 20_000, runMeters: 5_000)
        case .triathlonOlympic:
            EventDistanceComponents(swimMeters: 1_500, bikeMeters: 40_000, runMeters: 10_000)
        case .triathlon703:
            EventDistanceComponents(swimMeters: 1_900, bikeMeters: 90_000, runMeters: 21_097.5)
        case .triathlonCustom:
            EventDistanceComponents(swimMeters: 750, bikeMeters: 20_000, runMeters: 5_000)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(EventDistanceKind.self, forKey: .kind)
        components = (try? container.decodeIfPresent(EventDistanceComponents.self, forKey: .components))
            ?? Self.defaultComponents(for: kind)
    }
}

struct AthleteEventGoal: Codable, Equatable, Sendable {
    var sport: EventSport
    var distance: EventDistance?
    var eventDate: Date?
    var targetIntent: EventTargetIntent

    init(
        sport: EventSport,
        distance: EventDistance? = nil,
        eventDate: Date? = nil,
        targetIntent: EventTargetIntent = .complete
    ) {
        self.sport = sport
        self.distance = distance
        self.eventDate = eventDate
        self.targetIntent = targetIntent
    }

    var displayName: String {
        guard let distance else { return sport.displayName }
        return sport == .triathlon
            ? "\(distance.kind.displayName) Triathlon"
            : "\(distance.kind.displayName) \(sport.displayName)"
    }

    func daysRemaining(asOf date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let eventDate else { return nil }
        let start = calendar.startOfDay(for: date)
        let event = calendar.startOfDay(for: eventDate)
        return calendar.dateComponents([.day], from: start, to: event).day
    }

    /// Whole planning weeks remaining, rounded up so an event six days away is
    /// "1 week" rather than "0 weeks". Event day itself is 0.
    func weeksRemaining(asOf date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let days = daysRemaining(asOf: date, calendar: calendar), days >= 0 else { return nil }
        guard days > 0 else { return 0 }
        return (days + 6) / 7
    }

    func countdownLabel(asOf date: Date = .now, calendar: Calendar = .current) -> String? {
        guard let days = daysRemaining(asOf: date, calendar: calendar), days >= 0 else { return nil }
        if days == 0 { return "Today" }
        if days <= 7 { return days == 1 ? "1 day to go" : "\(days) days to go" }
        let weeks = (days + 6) / 7
        return weeks == 1 ? "1 week to go" : "\(weeks) weeks to go"
    }
}

struct TrainingObjective: Codable, Equatable, Sendable {
    var kind: TrainingObjectiveKind
    var event: AthleteEventGoal?

    init(kind: TrainingObjectiveKind, event: AthleteEventGoal? = nil) {
        self.kind = kind
        self.event = kind == .event ? event : nil
    }

    init(legacyGoal: TrainingGoal) {
        switch legacyGoal {
        case .generalFitness:
            self.init(kind: .generalFitness)
        case .improveEndurance:
            self.init(kind: .improveEndurance)
        case .returnToTraining:
            self.init(kind: .returnToTraining)
        case .firstTriathlon:
            self.init(
                kind: .event,
                event: AthleteEventGoal(
                    sport: .triathlon,
                    distance: nil,
                    eventDate: nil,
                    targetIntent: .complete
                )
            )
        }
    }

    var legacyGoal: TrainingGoal {
        switch kind {
        case .generalFitness: .generalFitness
        case .improveEndurance: .improveEndurance
        case .returnToTraining: .returnToTraining
        case .event:
            event?.sport == .triathlon ? .firstTriathlon : .improveEndurance
        }
    }

    var displayName: String {
        switch kind {
        case .generalFitness, .improveEndurance, .returnToTraining:
            kind.displayName
        case .event:
            event?.displayName ?? "Event / First Race"
        }
    }

    static func event(
        sport: EventSport,
        distance: EventDistance? = nil,
        eventDate: Date? = nil,
        targetIntent: EventTargetIntent = .complete
    ) -> TrainingObjective {
        TrainingObjective(
            kind: .event,
            event: AthleteEventGoal(
                sport: sport,
                distance: distance,
                eventDate: eventDate,
                targetIntent: targetIntent
            )
        )
    }
}

enum TrainingObjectiveValidationIssue: Equatable, Sendable {
    case eventDateInPast
    case missingTrainingSport(Sport)
    case eventDistanceSportMismatch
    case invalidEventDistance

    var message: String {
        switch self {
        case .eventDateInPast:
            "Choose today or a future event date."
        case .missingTrainingSport(let sport):
            "Add \(sport.displayName) to the sports you are training."
        case .eventDistanceSportMismatch:
            "Choose a distance that matches the selected event."
        case .invalidEventDistance:
            "Enter a distance greater than zero."
        }
    }
}

enum TrainingObjectiveValidator {
    static func issues(
        for objective: TrainingObjective,
        selectedSports: [Sport],
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> [TrainingObjectiveValidationIssue] {
        guard objective.kind == .event, let event = objective.event else { return [] }

        var issues: [TrainingObjectiveValidationIssue] = []
        let selected = Set(selectedSports)

        for sport in event.sport.requiredTrainingSports where !selected.contains(sport) {
            issues.append(.missingTrainingSport(sport))
        }

        if let distance = event.distance {
            if distance.kind.sport != event.sport {
                issues.append(.eventDistanceSportMismatch)
            } else if !distance.components.isValid(for: event.sport) {
                issues.append(.invalidEventDistance)
            }
        }

        if let eventDate = event.eventDate,
           calendar.startOfDay(for: eventDate) < calendar.startOfDay(for: date) {
            issues.append(.eventDateInPast)
        }

        return issues
    }
}

extension TrainingGoal {
    var trainingObjective: TrainingObjective { TrainingObjective(legacyGoal: self) }
}
