import Foundation

/// Headline figures for the Progress screen.
///
/// Derived on demand from the stored plans. Nothing here is persisted: these are
/// summaries of data we already hold, and caching them would only create a
/// second version of the truth to keep in sync.
struct TrainingStatistics: Equatable, Sendable {
    struct SportTotals: Equatable, Sendable, Identifiable {
        let sport: Sport
        let sessions: Int
        let duration: TimeInterval
        let distance: Double

        var id: Sport { sport }
    }

    var sessions: Int = 0
    var totalDuration: TimeInterval = 0
    var totalDistance: Double = 0
    var bySport: [SportTotals] = []
    var longestRunMeters: Double = 0
    var longestSwimMeters: Double = 0
    var longestRideSeconds: TimeInterval = 0
    var currentStreakDays: Int = 0

    var hasData: Bool { sessions > 0 }
}

extension TrainingStatistics {
    /// Only reported sessions count. A workout that was completed but never
    /// rated is still an unknown as far as training history goes.
    init(plans: [WeeklyPlan], now: Date = .now, calendar: Calendar = .current) {
        let reported = plans
            .flatMap(\.trainingSessions)
            .filter(\.hasReport)

        func duration(_ workout: PlannedWorkout) -> TimeInterval {
            workout.importedSummary?.duration ?? workout.estimatedDurationSeconds ?? 0
        }

        func distance(_ workout: PlannedWorkout) -> Double {
            workout.importedSummary?.distanceMeters ?? workout.estimatedDistanceMeters ?? 0
        }

        sessions = reported.count
        totalDuration = reported.reduce(0) { $0 + duration($1) }
        totalDistance = reported.reduce(0) { $0 + distance($1) }

        bySport = Sport.allCases.compactMap { sport in
            let sessions = reported.filter { $0.discipline.sport == sport }
            guard !sessions.isEmpty else { return nil }
            return SportTotals(
                sport: sport,
                sessions: sessions.count,
                duration: sessions.reduce(0) { $0 + duration($1) },
                distance: sessions.reduce(0) { $0 + distance($1) }
            )
        }

        longestRunMeters = reported
            .filter { $0.discipline == .running }
            .map(distance)
            .max() ?? 0
        longestSwimMeters = reported
            .filter { $0.discipline == .swimming }
            .map { $0.importedSummary?.longestContinuousSwimMeters ?? distance($0) }
            .max() ?? 0
        longestRideSeconds = reported
            .filter { $0.discipline == .cycling }
            .map(duration)
            .max() ?? 0

        currentStreakDays = Self.streak(endingAt: now, sessions: reported, calendar: calendar)
    }

    /// Consecutive days back from today that contain a reported session.
    ///
    /// Today not having one yet does not break the streak, since the day is not
    /// over; the count simply starts at yesterday.
    private static func streak(
        endingAt now: Date,
        sessions: [PlannedWorkout],
        calendar: Calendar
    ) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
