import Foundation

/// How training divided between the three sports (§39).
///
/// Time and load are kept apart rather than blended: an hour of easy cycling
/// and an hour of hard running are the same time and very different training,
/// and collapsing them would hide exactly that.
struct SportBalance: Equatable, Sendable {
    let secondsBySport: [Sport: TimeInterval]
    let loadBySport: [Sport: Double]

    var totalSeconds: TimeInterval { secondsBySport.values.reduce(0, +) }
    var totalLoad: Double { loadBySport.values.reduce(0, +) }

    func timeShare(_ sport: Sport) -> Double {
        totalSeconds > 0 ? (secondsBySport[sport] ?? 0) / totalSeconds : 0
    }

    /// Nil when nothing carried a load, so a sport is never shown as 0% when
    /// the truth is that nothing was measured.
    func loadShare(_ sport: Sport) -> Double? {
        totalLoad > 0 ? (loadBySport[sport] ?? 0) / totalLoad : nil
    }

    var hasLoad: Bool { totalLoad > 0 }
}

/// Compares the split that was planned with the split that happened.
struct SportBalanceComparison: Equatable, Sendable {
    let sport: Sport
    let plannedShare: Double
    let actualShare: Double

    var difference: Double { actualShare - plannedShare }
}

enum SportBalancePolicy {

    static func balance(of sessions: [LoadedSession]) -> IntelligenceValue<SportBalance> {
        guard !sessions.isEmpty else { return .unavailable }

        var seconds: [Sport: TimeInterval] = [:]
        var load: [Sport: Double] = [:]

        for session in sessions {
            if let duration = session.durationSeconds, duration > 0 {
                seconds[session.sport, default: 0] += duration
            }
            if let value = session.load?.value {
                load[session.sport, default: 0] += value
            }
        }

        guard !seconds.isEmpty || !load.isEmpty else { return .unavailable }
        return .available(SportBalance(secondsBySport: seconds, loadBySport: load))
    }

    /// Planned against actual, by time (§39).
    ///
    /// Every sport appearing in either side is reported, so a discipline that
    /// was planned and never done shows up as a shortfall rather than vanishing.
    static func compare(
        planned: [LoadedSession],
        actual: [LoadedSession]
    ) -> [SportBalanceComparison] {
        guard case .available(let plannedBalance) = balance(of: planned),
              case .available(let actualBalance) = balance(of: actual) else {
            return []
        }

        let sports = Set(plannedBalance.secondsBySport.keys)
            .union(actualBalance.secondsBySport.keys)

        return sports
            .map {
                SportBalanceComparison(
                    sport: $0,
                    plannedShare: plannedBalance.timeShare($0),
                    actualShare: actualBalance.timeShare($0)
                )
            }
            .sorted { $0.sport.displayName < $1.sport.displayName }
    }
}
