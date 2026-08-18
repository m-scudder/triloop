import Foundation

/// How much of a sport the athlete wants in a week, and how long a session of
/// it runs.
///
/// Stated intent rather than a quota: the planner will schedule fewer sessions
/// when the week cannot hold them, and safety can still pull a sport entirely.
struct SportPreference: Codable, Equatable, Sendable {
    /// Three is as many sessions of one sport as a beginner week should carry
    /// while still leaving room for the other two and for recovery.
    static let permittedSessions = 0...3

    var sport: Sport
    var sessionsPerWeek: Int
    /// How long the athlete expects a session to take, including warm-up and
    /// cooldown. Caps what the planner will place on a limited day.
    var typicalMinutes: Int

    init(sport: Sport, sessionsPerWeek: Int = 0, typicalMinutes: Int = 45) {
        self.sport = sport
        self.sessionsPerWeek = min(max(sessionsPerWeek, 0), Self.permittedSessions.upperBound)
        self.typicalMinutes = typicalMinutes
    }

    var isTrained: Bool { sessionsPerWeek > 0 }

    var typicalSeconds: TimeInterval { TimeInterval(typicalMinutes * 60) }

    /// Decoded key by key so a preference stored by an earlier build still
    /// loads once fields are added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }

        sport = value(.sport, Sport.running)
        sessionsPerWeek = value(.sessionsPerWeek, 0)
        typicalMinutes = value(.typicalMinutes, 45)
    }
}

extension SportPreference {
    /// A sensible opening position, so the athlete adjusts rather than starts
    /// from nothing. Session lengths match what week one actually prescribes.
    static func defaults(for baseline: AthleteBaseline) -> [SportPreference] {
        [
            SportPreference(
                sport: .running,
                sessionsPerWeek: baseline.running == .none ? 2 : 2,
                typicalMinutes: baseline.running.runsContinuously ? 45 : 30
            ),
            SportPreference(
                sport: .swimming,
                sessionsPerWeek: baseline.swimming == .none ? 1 : 2,
                typicalMinutes: 45
            ),
            SportPreference(
                sport: .cycling,
                sessionsPerWeek: 2,
                typicalMinutes: baseline.cycling.comfortableMinutes + 15
            )
        ]
    }
}
