import Foundation

/// Everything onboarding collects, stored as one value.
///
/// A single `Codable` property on `AthleteProfile` rather than a column per
/// answer: new questions can be added in a later phase without moving the
/// schema version, which is the same reason `TrainingParameters` is stored this
/// way. Every field decodes with a default so an older record still loads.
struct AthleteSetup: Codable, Equatable, Sendable {

    /// How far through onboarding the athlete got.
    ///
    /// Stored so an interrupted setup resumes where it stopped rather than
    /// starting again, and so "has this athlete been set up?" is an explicit
    /// answer rather than inferred from whether a plan happens to exist.
    enum Stage: String, Codable, CaseIterable, Sendable {
        case welcome
        case about
        case goal
        case running
        case swimming
        case cycling
        case days
        case commitment
        case pool
        case health
        case watch
        case preview
        case complete
        case safety

        static let onboardingFlow: [Stage] = [.running, .days, .preview]

        var consolidated: Stage {
            switch self {
            case .welcome: .running
            case .about, .goal: .days
            case .swimming, .cycling, .pool: .running
            case .commitment: .days
            case .health, .watch, .safety: .preview
            default: self
            }
        }

        /// Ordered as the flow runs, so resuming can pick the furthest reached.
        var order: Int {
            Self.onboardingFlow.firstIndex(of: consolidated) ?? Self.onboardingFlow.count
        }

        var next: Stage {
            guard order + 1 < Self.onboardingFlow.count else { return .complete }
            return Self.onboardingFlow[order + 1]
        }

        var previous: Stage {
            Self.onboardingFlow[max(min(order - 1, Self.onboardingFlow.count - 1), 0)]
        }
    }

    /// Structured source of truth for why the athlete is training.
    var objective: TrainingObjective

    /// Compatibility adapter for the existing adaptive engine. Phase A does
    /// not change how workload progression works; event-aware periodisation is
    /// layered above it in Phase B.
    var goal: TrainingGoal {
        get { objective.legacyGoal }
        set { objective = TrainingObjective(legacyGoal: newValue) }
    }

    var baseline: AthleteBaseline
    /// Anchors heart-rate zones. Optional because zones report Unavailable
    /// rather than guessing when the athlete would rather not say.
    var birthDate: Date?
    var schedule: AthleteSchedule
    /// User-selected date for the first generated plan. Optional for profiles
    /// created before this onboarding question existed.
    var planStartDate: Date?
    /// Selected sports and their automatically assigned opening frequency.
    var preferences: [SportPreference]
    var stage: Stage
    var completedAt: Date?

    init(
        goal: TrainingGoal = .generalFitness,
        objective: TrainingObjective? = nil,
        baseline: AthleteBaseline = AthleteBaseline(),
        birthDate: Date? = nil,
        schedule: AthleteSchedule = .empty,
        planStartDate: Date? = nil,
        preferences: [SportPreference] = [],
        stage: Stage = .welcome,
        completedAt: Date? = nil
    ) {
        self.objective = objective ?? TrainingObjective(legacyGoal: goal)
        self.baseline = baseline
        self.birthDate = birthDate
        self.schedule = schedule
        self.planStartDate = planStartDate
        self.preferences = preferences
        self.stage = stage
        self.completedAt = completedAt
    }

    var isComplete: Bool { stage == .complete && completedAt != nil }

    var selectedSports: [Sport] {
        preferences.filter(\.isTrained).map(\.sport)
    }

    func objectiveValidationIssues(
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> [TrainingObjectiveValidationIssue] {
        TrainingObjectiveValidator.issues(
            for: objective,
            selectedSports: selectedSports,
            asOf: date,
            calendar: calendar
        )
    }

    private enum CodingKeys: String, CodingKey {
        case objective
        case goal
        case baseline
        case birthDate
        case schedule
        case planStartDate
        case preferences
        case stage
        case completedAt
    }

    /// Enough information to build a week. Checked before generation so an
    /// interrupted setup can never produce a plan from half an assessment.
    var canGeneratePlan: Bool {
        schedule.isUsable && preferences.contains(where: \.isTrained)
    }

    /// Decoded key by key so a setup stored by an earlier build still loads once
    /// questions are added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AthleteSetup()

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            do {
                return try container.decodeIfPresent(T.self, forKey: key) ?? fallback
            } catch {
                return fallback
            }
        }

        let legacyGoal = value(.goal, defaults.goal)
        objective = (try? container.decodeIfPresent(TrainingObjective.self, forKey: .objective))
            ?? TrainingObjective(legacyGoal: legacyGoal)
        baseline = value(.baseline, defaults.baseline)
        birthDate = (try? container.decodeIfPresent(Date.self, forKey: .birthDate)) ?? nil
        schedule = value(.schedule, defaults.schedule)
        planStartDate = (try? container.decodeIfPresent(Date.self, forKey: .planStartDate)) ?? nil
        preferences = value(.preferences, defaults.preferences)
        stage = value(.stage, defaults.stage)
        completedAt = (try? container.decodeIfPresent(Date.self, forKey: .completedAt)) ?? nil
    }

    /// Write both the structured objective and its coarse adapter. Keeping the
    /// legacy key makes backups and older fixtures readable while the new
    /// objective remains the authoritative representation.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(objective, forKey: .objective)
        try container.encode(goal, forKey: .goal)
        try container.encode(baseline, forKey: .baseline)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encode(schedule, forKey: .schedule)
        try container.encodeIfPresent(planStartDate, forKey: .planStartDate)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(stage, forKey: .stage)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}
