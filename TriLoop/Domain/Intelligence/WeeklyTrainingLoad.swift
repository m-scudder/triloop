import Foundation

/// One completed session reduced to what weekly aggregation needs.
///
/// A value type rather than a `PlannedWorkout` so the intelligence layer stays
/// free of SwiftData.
struct LoadedSession: Equatable, Sendable {
    let date: Date
    let sport: Sport
    /// Nil when the session happened but nothing measured it.
    let load: SessionLoad?
    let durationSeconds: TimeInterval?
    let intensity: WorkoutIntensity?
    let distanceMeters: Double?
    let averageHeartRate: Double?
    /// Longest unbroken swim, which is what §45 progresses on.
    let longestContinuousSwimMeters: Double?
    /// Sensor values, reusing the existing bag rather than restating it.
    let metrics: RecordedMetrics

    init(
        date: Date,
        sport: Sport,
        load: SessionLoad? = nil,
        durationSeconds: TimeInterval? = nil,
        intensity: WorkoutIntensity? = nil,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        longestContinuousSwimMeters: Double? = nil,
        metrics: RecordedMetrics = RecordedMetrics()
    ) {
        self.date = date
        self.sport = sport
        self.load = load
        self.durationSeconds = durationSeconds
        self.intensity = intensity
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.longestContinuousSwimMeters = longestContinuousSwimMeters
        self.metrics = metrics
    }

    /// Seconds per kilometre. Nil unless both distance and time were recorded.
    var pacePerKilometre: Double? {
        guard let distanceMeters, distanceMeters > 0, let durationSeconds else { return nil }
        return durationSeconds / (distanceMeters / 1_000)
    }

    /// Seconds per 100 m of elapsed swimming, rests included.
    ///
    /// §45 forbids mixing this with active pace, so the two never share a name.
    var elapsedSwimPacePer100m: Double? {
        guard sport == .swimming, let distanceMeters, distanceMeters > 0,
              let durationSeconds else { return nil }
        return durationSeconds / (distanceMeters / 100)
    }
}

/// Sessions belonging to one TriLoop plan week.
///
/// §37 aggregates by plan week rather than by `Calendar` week on purpose: the
/// locale's first weekday is not the athlete's, and grouping by it would split
/// a training week across two totals.
struct PlanWeekSessions: Equatable, Sendable {
    let weekNumber: Int
    let startDate: Date
    let sessions: [LoadedSession]

    init(weekNumber: Int, startDate: Date, sessions: [LoadedSession]) {
        self.weekNumber = weekNumber
        self.startDate = startDate
        self.sessions = sessions
    }
}

/// What a week of training added up to.
struct WeeklyLoad: Equatable, Sendable {
    let weekNumber: Int
    let startDate: Date
    let total: Double
    let bySport: [Sport: Double]
    /// Sessions that carried a load, and sessions that happened without one.
    let measured: Int
    let unmeasured: Int

    /// Lets the UI qualify a total built from partial evidence rather than
    /// presenting it as complete.
    var isPartial: Bool { unmeasured > 0 }
}

/// Totals a week and compares it with recent history (§37).
enum WeeklyTrainingLoad {

    /// Weeks needed before a rolling average means anything.
    static let rollingWindow = 4

    static func load(for week: PlanWeekSessions) -> IntelligenceValue<WeeklyLoad> {
        let measured = week.sessions.compactMap { session in
            session.load.map { (session.sport, $0.value) }
        }

        // A week where nothing was measured has no total. Reporting zero would
        // claim the athlete did nothing, which is a different statement.
        guard !measured.isEmpty else { return .unavailable }

        var bySport: [Sport: Double] = [:]
        for (sport, value) in measured {
            bySport[sport, default: 0] += value
        }

        return .available(
            WeeklyLoad(
                weekNumber: week.weekNumber,
                startDate: week.startDate,
                total: measured.reduce(0) { $0 + $1.1 },
                bySport: bySport,
                measured: measured.count,
                unmeasured: week.sessions.count - measured.count
            )
        )
    }

    /// Mean of the most recent complete weeks.
    ///
    /// Requires the full window: averaging two weeks and calling it a four-week
    /// average would misrepresent how settled the figure is.
    static func rollingAverage(
        of weeks: [WeeklyLoad],
        window: Int = rollingWindow
    ) -> IntelligenceValue<Double> {
        guard weeks.count >= window else {
            return .insufficientHistory(found: weeks.count, required: window)
        }

        let recent = weeks.sorted { $0.startDate > $1.startDate }.prefix(window)
        return .available(recent.reduce(0) { $0 + $1.total } / Double(window))
    }

    /// Change from one week to the next, as a fraction.
    ///
    /// Nil when the previous week had no load to compare against: a rise from
    /// nothing is not a percentage.
    static func change(from previous: WeeklyLoad?, to current: WeeklyLoad?) -> Double? {
        guard let current, let previous, previous.total > 0 else { return nil }
        return (current.total - previous.total) / previous.total
    }

    /// Share of the week's load carried by each sport (§39).
    static func balance(of week: WeeklyLoad) -> [Sport: Double] {
        guard week.total > 0 else { return [:] }
        return week.bySport.mapValues { $0 / week.total }
    }
}
