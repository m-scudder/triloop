import Foundation

/// What the athlete can run today, asked as ability rather than a self-applied
/// label. "Intermediate" means nothing consistent between two people; "I can
/// run continuously for 20 minutes" does.
enum RunningBaseline: String, Codable, CaseIterable, Sendable {
    case none
    case runWalk
    case continuous10Minutes
    case continuous20To30Minutes
    case regular5K

    var question: String { "How comfortable are you with running today?" }

    var displayName: String {
        switch self {
        case .none: "I don't currently run"
        case .runWalk: "I can run and walk for 15–20 minutes"
        case .continuous10Minutes: "I can run continuously for around 10 minutes"
        case .continuous20To30Minutes: "I can run continuously for 20–30 minutes"
        case .regular5K: "I regularly run 5 km or more"
        }
    }

    /// True once walk breaks are no longer the point of the session.
    var runsContinuously: Bool {
        switch self {
        case .none, .runWalk: false
        case .continuous10Minutes, .continuous20To30Minutes, .regular5K: true
        }
    }
}

/// Longest distance the athlete can swim without stopping.
///
/// Continuity rather than total volume, because that is what limits a beginner
/// and what the swim progression works on.
enum SwimmingBaseline: String, Codable, CaseIterable, Sendable {
    case none
    case continuous25
    case continuous50
    case continuous100
    case continuous200Plus

    var question: String { "What's the longest you can comfortably swim without stopping?" }

    var displayName: String {
        switch self {
        case .none: "Not yet able to swim continuously"
        case .continuous25: "25 m"
        case .continuous50: "50 m"
        case .continuous100: "100 m"
        case .continuous200Plus: "200 m or more"
        }
    }

    /// Metres the athlete can cover unbroken. `nil` when they cannot yet swim a
    /// length, which is a different situation from swimming a short one.
    var continuousMeters: Double? {
        switch self {
        case .none: nil
        case .continuous25: 25
        case .continuous50: 50
        case .continuous100: 100
        case .continuous200Plus: 200
        }
    }
}

/// Primary stroke. Only two options while nothing in the engine is
/// stroke-specific; more would be a field with no reader.
enum SwimStroke: String, Codable, CaseIterable, Sendable {
    case freestyle
    case mixed

    var displayName: String {
        switch self {
        case .freestyle: "Freestyle"
        case .mixed: "Mixed"
        }
    }
}

/// How long the athlete can ride continuously.
enum CyclingBaseline: String, Codable, CaseIterable, Sendable {
    case under20
    case twentyToThirty
    case thirtyToFortyFive
    case fortyFiveToSixty
    case sixtyPlus

    var question: String { "How long can you comfortably cycle continuously?" }

    var displayName: String {
        switch self {
        case .under20: "Less than 20 minutes"
        case .twentyToThirty: "20–30 minutes"
        case .thirtyToFortyFive: "30–45 minutes"
        case .fortyFiveToSixty: "45–60 minutes"
        case .sixtyPlus: "60 minutes or more"
        }
    }

    /// The conservative end of the stated range: a first week should be
    /// comfortably inside what the athlete already does.
    var comfortableMinutes: Int {
        switch self {
        case .under20: 15
        case .twentyToThirty: 20
        case .thirtyToFortyFive: 30
        case .fortyFiveToSixty: 45
        case .sixtyPlus: 60
        }
    }
}

/// The athlete's self-assessed starting point, per sport.
///
/// A snapshot of ability at a moment, not a running record of fitness. Training
/// history is what tracks change; this is only ever the seed for it.
struct AthleteBaseline: Codable, Equatable, Sendable {
    var running: RunningBaseline
    var swimming: SwimmingBaseline
    var stroke: SwimStroke
    var cycling: CyclingBaseline
    var assessedAt: Date

    init(
        running: RunningBaseline = .none,
        swimming: SwimmingBaseline = .none,
        stroke: SwimStroke = .freestyle,
        cycling: CyclingBaseline = .under20,
        assessedAt: Date = .now
    ) {
        self.running = running
        self.swimming = swimming
        self.stroke = stroke
        self.cycling = cycling
        self.assessedAt = assessedAt
    }

    /// Decoded key by key so a baseline stored by an earlier build still loads
    /// once fields are added. The synthesised decoder would throw on the missing
    /// keys and take the whole profile with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AthleteBaseline()

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }

        running = value(.running, defaults.running)
        swimming = value(.swimming, defaults.swimming)
        stroke = value(.stroke, defaults.stroke)
        cycling = value(.cycling, defaults.cycling)
        assessedAt = value(.assessedAt, defaults.assessedAt)
    }
}
