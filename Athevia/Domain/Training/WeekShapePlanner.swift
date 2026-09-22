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
/// Deterministic: the same schedule and selected sports always produce the same
/// week. An available day is a plan slot; selected sports are balanced across
/// those slots and recovery fills any slot that should not carry another run.
struct WeekShapePlanner: Sendable {
    /// Running is the only high-impact sport here, so it is the only one given
    /// a hard no-consecutive-days rule where the available shape allows it.
    var highImpact: Set<Sport> = [.running]

    func plan(
        schedule: AthleteSchedule,
        frequencies: [SportFrequency],
        durations: [Sport: TimeInterval] = [:]
    ) -> WeekShape {
        var placed: [Weekday: Sport] = [:]
        var unplaced: [Sport: Int] = [:]

        let fillsEveryAvailableDay =
            frequencies.reduce(0) { $0 + max($1.sessions, 0) } >= schedule.availableDays.count

        // When all available days are being filled, place running first so its
        // recovery spacing is protected before low-impact sports consume the
        // separating days. Otherwise keep the longest-session-first behaviour.
        let ordered = frequencies
            .filter { $0.sessions > 0 }
            .sorted { lhs, rhs in
                if fillsEveryAvailableDay {
                    let leftHighImpact = highImpact.contains(lhs.sport)
                    let rightHighImpact = highImpact.contains(rhs.sport)
                    if leftHighImpact != rightHighImpact {
                        return leftHighImpact && !rightHighImpact
                    }
                }

                let left = durations[lhs.sport] ?? 0
                let right = durations[rhs.sport] ?? 0
                if left != right { return left > right }
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

    /// Days the athlete can train and that a session of this sport would fit.
    private func candidates(
        for sport: Sport,
        schedule: AthleteSchedule,
        durations: [Sport: TimeInterval]
    ) -> [Weekday] {
        Weekday.trainingWeek.filter { weekday in
            let availability = schedule.availability(on: weekday)
            return availability.isAvailable && availability.accommodates(seconds: durations[sport])
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

        // Falling back to free keeps a cramped schedule viable when there is no
        // other way to place what was prescribed.
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
    /// Builds the weekly sport mix from selected sports and available days.
    ///
    /// Availability defines the number of plan slots. The old per-sport
    /// sessions-per-week values are intentionally ignored here; onboarding no
    /// longer asks for frequency. Extra slots favour lower-impact sports before
    /// running. When running is the only sport, only non-consecutive available
    /// days receive runs and the remaining available slots become recovery.
    static func frequencies(
        from preferences: [SportPreference],
        schedule: AthleteSchedule
    ) -> [SportFrequency] {
        frequencies(
            for: preferences.filter(\.isTrained).map(\.sport),
            schedule: schedule
        )
    }

    static func frequencies(
        for sports: [Sport],
        schedule: AthleteSchedule
    ) -> [SportFrequency] {
        let selected = Sport.allCases.filter { sports.contains($0) }
        let slots = schedule.availableDays.count

        guard slots > 0, !selected.isEmpty else { return [] }

        if selected == [.running] {
            return [
                SportFrequency(
                    sport: .running,
                    sessions: safeRunningSessions(in: schedule)
                )
            ]
        }

        var counts = Dictionary(uniqueKeysWithValues: selected.map { ($0, 0) })
        var remaining = slots

        // Every selected sport gets represented before additional days are
        // distributed.
        for sport in selected where remaining > 0 {
            counts[sport, default: 0] += 1
            remaining -= 1
        }

        // Lower-impact sports receive an odd spare slot before running.
        let allocationOrder: [Sport] = [.swimming, .cycling, .running]
            .filter { selected.contains($0) }

        while remaining > 0 {
            for sport in allocationOrder where remaining > 0 {
                counts[sport, default: 0] += 1
                remaining -= 1
            }
        }

        return selected.compactMap { sport in
            guard let count = counts[sport], count > 0 else { return nil }
            return SportFrequency(sport: sport, sessions: count)
        }
    }

    private static func safeRunningSessions(in schedule: AthleteSchedule) -> Int {
        var count = 0
        var previousRunOffset: Int?

        for day in schedule.availableDays.map(\.weekday) {
            if let previousRunOffset,
               day.offsetFromMonday - previousRunOffset < 2 {
                continue
            }

            count += 1
            previousRunOffset = day.offsetFromMonday
        }

        return count
    }
}
