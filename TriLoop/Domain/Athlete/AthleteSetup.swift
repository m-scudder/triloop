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

        /// Ordered as the flow runs, so resuming can pick the furthest reached.
        var order: Int {
            Self.allCases.firstIndex(of: self) ?? 0
        }

        var next: Stage {
            let index = min(order + 1, Self.allCases.count - 1)
            return Self.allCases[index]
        }

        var previous: Stage {
            Self.allCases[max(order - 1, 0)]
        }
    }

    var goal: TrainingGoal
    var baseline: AthleteBaseline
    /// Anchors heart-rate zones. Optional because zones report Unavailable
    /// rather than guessing when the athlete would rather not say.
    var birthDate: Date?
    var schedule: AthleteSchedule
    /// How much of each sport the athlete wants. Empty until the commitment
    /// step, which seeds it from the baselines.
    var preferences: [SportPreference]
    var stage: Stage
    var completedAt: Date?

    init(
        goal: TrainingGoal = .generalFitness,
        baseline: AthleteBaseline = AthleteBaseline(),
        birthDate: Date? = nil,
        schedule: AthleteSchedule = .empty,
        preferences: [SportPreference] = [],
        stage: Stage = .welcome,
        completedAt: Date? = nil
    ) {
        self.goal = goal
        self.baseline = baseline
        self.birthDate = birthDate
        self.schedule = schedule
        self.preferences = preferences
        self.stage = stage
        self.completedAt = completedAt
    }

    var isComplete: Bool { stage == .complete && completedAt != nil }

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
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }

        goal = value(.goal, defaults.goal)
        baseline = value(.baseline, defaults.baseline)
        birthDate = (try? container.decodeIfPresent(Date.self, forKey: .birthDate)) ?? nil
        schedule = value(.schedule, defaults.schedule)
        preferences = value(.preferences, defaults.preferences)
        stage = value(.stage, defaults.stage)
        completedAt = (try? container.decodeIfPresent(Date.self, forKey: .completedAt)) ?? nil
    }
}
