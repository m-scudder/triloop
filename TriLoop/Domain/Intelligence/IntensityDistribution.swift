import Foundation

/// How training time was split between easy, moderate and hard (§38).
struct IntensityDistribution: Equatable, Sendable {
    let secondsByIntensity: [WorkoutIntensity: TimeInterval]
    /// Sessions that could be classified, and sessions that could not.
    let measured: Int
    let unmeasured: Int

    var totalSeconds: TimeInterval {
        secondsByIntensity.values.reduce(0, +)
    }

    func seconds(_ intensity: WorkoutIntensity) -> TimeInterval {
        secondsByIntensity[intensity] ?? 0
    }

    /// Derived rather than stored, so shares cannot drift from the durations.
    func share(_ intensity: WorkoutIntensity) -> Double {
        totalSeconds > 0 ? seconds(intensity) / totalSeconds : 0
    }

    var isPartial: Bool { unmeasured > 0 }
}

/// Splits training time across the three intensity bands.
///
/// Descriptive only. §38 is explicit that TriLoop does not prescribe a
/// universal easy-to-hard ratio: polarised, pyramidal and threshold models all
/// disagree, and the athlete's own trend is the useful comparison.
enum IntensityDistributionPolicy {

    /// Passing a sport answers "where is my hard work going?" per discipline.
    static func distribution(
        for sessions: [LoadedSession],
        sport: Sport? = nil
    ) -> IntelligenceValue<IntensityDistribution> {
        let relevant = sport.map { wanted in sessions.filter { $0.sport == wanted } } ?? sessions
        guard !relevant.isEmpty else { return .unavailable }

        var seconds: [WorkoutIntensity: TimeInterval] = [:]
        var measured = 0

        for session in relevant {
            // Both are required: an intensity with no duration cannot be
            // weighted, and a duration with no intensity has no band to sit in.
            guard let intensity = session.intensity,
                  let duration = session.durationSeconds,
                  duration > 0 else { continue }

            seconds[intensity, default: 0] += duration
            measured += 1
        }

        guard measured > 0 else { return .unavailable }

        return .available(
            IntensityDistribution(
                secondsByIntensity: seconds,
                measured: measured,
                unmeasured: relevant.count - measured
            )
        )
    }

    /// Sports that actually appear, so a drill-down offers no empty tabs.
    static func sportsPresent(in sessions: [LoadedSession]) -> [Sport] {
        var seen: [Sport] = []
        for session in sessions where !seen.contains(session.sport) {
            seen.append(session.sport)
        }
        return seen
    }
}
