import Foundation

/// The three sports Athevia trains and evaluates independently.
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
    case multisport
    case recovery
    case rest

    var sport: Sport? {
        switch self {
        case .running: .running
        case .swimming: .swimming
        case .cycling: .cycling
        case .multisport, .recovery, .rest: nil
        }
    }

    /// Sessions that contribute physiological training load and sport progression.
    /// Recovery is deliberately excluded from load even though it is a workout.
    var isTrainingSession: Bool { self != .recovery && self != .rest }

    /// Anything the athlete is actively asked to complete counts as a workout.
    /// Rest is passive and never enters workout totals, completion, or adherence.
    var isPlannedWorkout: Bool { self != .rest }

    var displayName: String {
        switch self {
        case .running: "Run"
        case .swimming: "Swim"
        case .cycling: "Cycle"
        case .multisport: "Multisport"
        case .recovery: "Recovery"
        case .rest: "Rest"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .swimming: "figure.pool.swim"
        case .cycling: "figure.outdoor.cycle"
        case .multisport: "figure.mixed.cardio"
        case .recovery: "figure.cooldown"
        case .rest: "moon.zzz.fill"
        }
    }
}
