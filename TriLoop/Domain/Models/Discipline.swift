import Foundation

/// The three sports TriLoop trains and evaluates independently.
///
/// Kept deliberately separate from `Discipline` so the future sport-specific
/// training engines can only ever be handed a real sport, never a rest day.
enum Sport: String, Codable, CaseIterable, Sendable {
    case running
    case swimming
    case cycling

    var displayName: String {
        switch self {
        case .running: "Running"
        case .swimming: "Swimming"
        case .cycling: "Cycling"
        }
    }

    var discipline: Discipline {
        switch self {
        case .running: .running
        case .swimming: .swimming
        case .cycling: .cycling
        }
    }
}

/// What a given day in a weekly plan actually is.
enum Discipline: String, Codable, CaseIterable, Sendable {
    case running
    case swimming
    case cycling
    case recovery
    case rest

    var sport: Sport? {
        switch self {
        case .running: .running
        case .swimming: .swimming
        case .cycling: .cycling
        case .recovery, .rest: nil
        }
    }

    /// Recovery and rest days are still scheduled, but they are never progressed.
    var isTrainingSession: Bool { sport != nil }

    var displayName: String {
        switch self {
        case .running: "Run"
        case .swimming: "Swim"
        case .cycling: "Cycle"
        case .recovery: "Recovery"
        case .rest: "Rest"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .swimming: "figure.pool.swim"
        case .cycling: "figure.outdoor.cycle"
        case .recovery: "figure.cooldown"
        case .rest: "moon.zzz.fill"
        }
    }
}
