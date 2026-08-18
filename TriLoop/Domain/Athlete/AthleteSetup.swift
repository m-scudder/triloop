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
        case goal
        case running
        case swimming
        case cycling
        case availability
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
    var schedule: AthleteSchedule
    var stage: Stage
    var completedAt: Date?

    init(
        goal: TrainingGoal = .generalFitness,
        baseline: AthleteBaseline = AthleteBaseline(),
        schedule: AthleteSchedule = .empty,
        stage: Stage = .welcome,
        completedAt: Date? = nil
    ) {
        self.goal = goal
        self.baseline = baseline
        self.schedule = schedule
        self.stage = stage
        self.completedAt = completedAt
    }

    var isComplete: Bool { stage == .complete && completedAt != nil }

    /// Enough information to build a week. Checked before generation so an
    /// interrupted setup can never produce a plan from half an assessment.
    var canGeneratePlan: Bool {
        schedule.isUsable && !schedule.trainableSports.isEmpty
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
        schedule = value(.schedule, defaults.schedule)
        stage = value(.stage, defaults.stage)
        completedAt = (try? container.decodeIfPresent(Date.self, forKey: .completedAt)) ?? nil
    }
}
