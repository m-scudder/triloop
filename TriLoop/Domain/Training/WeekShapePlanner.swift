import Foundation

/// How many sessions of each sport a week should carry.
struct SportFrequency: Equatable, Sendable {
    var sport: Sport
    var sessions: Int
}

/// The result of fitting a week's sessions into the athlete's availability.
struct WeekShape: Equatable, Sendable {
    /// Seven disciplines, Monday first.
    var disciplines: [Discipline]
    /// Sessions that could not be placed, by sport. Empty when everything fitted.
    var unplaced: [Sport: Int]

    /// A week with at least one training session in it. A shape that placed
    /// nothing is reported rather than silently returned as a week of rest.
    var isViable: Bool {
        disciplines.contains { $0.isTrainingSession }
    }

    var fittedEverything: Bool { unplaced.isEmpty }
}

/// Places a week's sessions on the days the athlete can actually train.
///
/// Deterministic: the same schedule and frequencies always produce the same
/// week. Availability is an input to *scheduling* only — it never changes what
/// the engine decided to prescribe.
struct WeekShapePlanner: Sendable {
    /// Running is the only high-impact sport here, so it is the only one given
    /// a hard no-consecutive-days rule.
    var highImpact: Set<Sport> = [.running]

    func plan(
        schedule: AthleteSchedule,
        frequencies: [SportFrequency],
        durations: [Sport: TimeInterval] = [:]
    ) -> WeekShape {
        var placed: [Weekday: Sport] = [:]
        var unplaced: [Sport: Int] = [:]

        // Scarcest sport first: a sport with one possible day must claim it
        // before a sport that could go anywhere takes it.
        let ordered = frequencies
            .filter { $0.sessions > 0 }
            .sorted { lhs, rhs in
                let left = candidates(for: lhs.sport, schedule: schedule, durations: durations).count
                let right = candidates(for: rhs.sport, schedule: schedule, durations: durations).count
                if left != right { return left < right }
                return lhs.sport.rawValue < rhs.sport.rawValue
            }

        for frequency in ordered {
            let options = candidates(for: frequency.sport, schedule: schedule, durations: durations)
            var remaining = frequency.sessions

            while remaining > 0 {
                guard let day = bestDay(
                    for: frequency.sport,
                    among: options,
                    placed: placed
                ) else { break }

                placed[day] = frequency.sport
                remaining -= 1
            }

            if remaining > 0 { unplaced[frequency.sport] = remaining }
        }

        let disciplines = Weekday.trainingWeek.map { weekday in
            placed[weekday]?.discipline ?? .rest
        }

        return WeekShape(disciplines: disciplines, unplaced: unplaced)
    }

    /// Days the athlete allows this sport and that a session of it would fit.
    private func candidates(
        for sport: Sport,
        schedule: AthleteSchedule,
        durations: [Sport: TimeInterval]
    ) -> [Weekday] {
        Weekday.trainingWeek.filter { weekday in
            let availability = schedule.availability(on: weekday)
            return availability.allows(sport) && availability.accommodates(seconds: durations[sport])
        }
    }

    /// Picks the free day furthest from anything already scheduled, so sessions
    /// spread across the week rather than clustering at the front of it.
    private func bestDay(
        for sport: Sport,
        among options: [Weekday],
        placed: [Weekday: Sport]
    ) -> Weekday? {
        let free = options.filter { placed[$0] == nil }
        guard !free.isEmpty else { return nil }

        let sameSport = placed.filter { $0.value == sport }.keys
        let adjacentBlocked = highImpact.contains(sport)

        let allowed = free.filter { day in
            guard adjacentBlocked else { return true }
            return !sameSport.contains { abs($0.offsetFromMonday - day.offsetFromMonday) < 2 }
        }

        // Falling back to `free` keeps a cramped schedule viable: two runs on
        // consecutive days is worse than spacing, but better than one run.
        let pool = allowed.isEmpty ? free : allowed

        return pool.max { lhs, rhs in
            let left = (spacing(lhs, from: sameSport), spacing(lhs, from: placed.keys))
            let right = (spacing(rhs, from: sameSport), spacing(rhs, from: placed.keys))
            if left != right { return left < right }
            // Earliest day wins ties, so the result never depends on set order.
            return lhs.offsetFromMonday > rhs.offsetFromMonday
        }
    }

    private func spacing(_ day: Weekday, from days: some Collection<Weekday>) -> Int {
        days
            .map { abs($0.offsetFromMonday - day.offsetFromMonday) }
            .min() ?? Int.max
    }
}

extension WeekShapePlanner {
    /// The default weekly frequency for a sport the athlete can train.
    ///
    /// Two sessions is what the existing three-sport week carries, and it is
    /// the least that lets a sport be progressed on evidence rather than a
    /// single data point. Capped by how many days actually allow it.
    static func defaultFrequencies(
        for schedule: AthleteSchedule,
        preferred: Int = 2
    ) -> [SportFrequency] {
        Sport.allCases.compactMap { sport in
            let days = schedule.availableDays.filter { $0.allows(sport) }.count
            guard days > 0 else { return nil }
            return SportFrequency(sport: sport, sessions: min(preferred, days))
        }
    }
}
