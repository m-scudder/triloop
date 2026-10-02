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
        schedule: AthleteSchedule,
        sessionLimit: Int? = nil
    ) -> [SportFrequency] {
        let selected = Sport.allCases.filter { sports.contains($0) }
        let slots = min(schedule.availableDays.count, sessionLimit ?? schedule.availableDays.count)

        guard slots > 0, !selected.isEmpty else { return [] }

        if selected == [.running] {
            return [
                SportFrequency(
                    sport: .running,
                    sessions: min(slots, safeRunningSessions(in: schedule))
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

    /// Redistributes the same available slots toward journey priorities.
    /// It never creates extra days and never bypasses the planner's run-spacing
    /// rule. Every selected sport remains represented when slots allow.
    static func frequencies(
        for sports: [Sport],
        schedule: AthleteSchedule,
        priorities: [SportPriority],
        sessionLimit: Int? = nil
    ) -> [SportFrequency] {
        let selected = Sport.allCases.filter { sports.contains($0) }
        let slots = min(schedule.availableDays.count, sessionLimit ?? schedule.availableDays.count)
        guard slots > 0, !selected.isEmpty else { return [] }
        if selected == [.running] {
            return frequencies(for: selected, schedule: schedule, sessionLimit: slots)
        }

        var counts = Dictionary(uniqueKeysWithValues: selected.map { ($0, 0) })
        var remaining = slots

        for sport in selected where remaining > 0 {
            counts[sport, default: 0] += 1
            remaining -= 1
        }

        let ranked = priorities
            .filter { selected.contains($0.sport) }
            .sorted { $0.rank < $1.rank }
            .map(\.sport)
        let order = ranked + selected.filter { !ranked.contains($0) }

        var index = 0
        while remaining > 0, !order.isEmpty {
            let sport = order[index % order.count]
            if sport != .running || counts[sport, default: 0] < safeRunningSessions(in: schedule) {
                counts[sport, default: 0] += 1
                remaining -= 1
            }
            index += 1
            if index > slots * max(order.count, 1) * 2 { break }
        }

        return selected.compactMap { sport in
            guard let count = counts[sport], count > 0 else { return nil }
            return SportFrequency(sport: sport, sessions: count)
        }
    }

    /// Opening frequency derived from the athlete's sport-specific onboarding
    /// ability. Availability is a ceiling, not a quota: a new athlete can say
    /// six days are possible without being assigned six training sessions.
    static func frequencies(
        for sports: [Sport],
        schedule: AthleteSchedule,
        baseline: AthleteBaseline,
        priorities: [SportPriority] = [],
        sessionLimit: Int? = nil
    ) -> [SportFrequency] {
        let scores: [Sport: Int] = [
            .running: baseline.running.experienceScore,
            .swimming: baseline.swimming.experienceScore,
            .cycling: baseline.cycling.experienceScore
        ]
        return capacityAwareFrequencies(
            for: sports,
            schedule: schedule,
            experienceScores: scores,
            priorities: priorities,
            sessionLimit: sessionLimit
        )
    }

    /// The same capacity rule after onboarding, now driven by current capability
    /// rather than permanently freezing the initial self-assessment.
    static func frequencies(
        for sports: [Sport],
        schedule: AthleteSchedule,
        capability: AthleteCapabilityAssessment,
        priorities: [SportPriority] = [],
        sessionLimit: Int? = nil
    ) -> [SportFrequency] {
        let scores: [Sport: Int] = [
            .running: runningExperienceScore(capability.running),
            .swimming: swimmingExperienceScore(capability.swimming),
            .cycling: cyclingExperienceScore(capability.cycling)
        ]
        return capacityAwareFrequencies(
            for: sports,
            schedule: schedule,
            experienceScores: scores,
            priorities: priorities,
            sessionLimit: sessionLimit
        )
    }

    private static func capacityAwareFrequencies(
        for sports: [Sport],
        schedule: AthleteSchedule,
        experienceScores: [Sport: Int],
        priorities: [SportPriority],
        sessionLimit: Int?
    ) -> [SportFrequency] {
        let selected = Sport.allCases.filter { sports.contains($0) }
        let requestedLimit = sessionLimit.map { max($0, selected.count) } ?? schedule.availableDays.count
        let available = min(schedule.availableDays.count, requestedLimit)
        guard available > 0, !selected.isEmpty else { return [] }

        // An explicit weekly target owns frequency. Running still keeps its
        // non-consecutive-day placement rule, but baseline experience must not
        // silently reduce a user-selected 3-day week back to 2.
        if selected == [.running], let sessionLimit {
            return [
                SportFrequency(
                    sport: .running,
                    sessions: min(available, sessionLimit, safeRunningSessions(in: schedule))
                )
            ]
        }

        // Low-impact single-sport plans can use the days the athlete explicitly
        // selected. Intensity and duration remain capability-controlled.
        if selected == [.cycling] {
            return [SportFrequency(sport: .cycling, sessions: available)]
        }
        if selected == [.swimming] {
            let swimScore = experienceScores[.swimming, default: 0]
            let safeSwimDays = swimScore <= 1 ? min(available, 5) : available
            return [SportFrequency(sport: .swimming, sessions: safeSwimDays)]
        }

        let scores = selected.map { Double(experienceScores[$0, default: 0]) }
        let average = scores.reduce(0, +) / Double(scores.count)
        let minimum = scores.min() ?? 0
        // A weak discipline matters in multisport training, but does not erase
        // capability already established in the other sports.
        let capacityScore = (average * 0.7) + (minimum * 0.3)
        let target: Int
        if sessionLimit != nil {
            target = available
        } else {
            target = min(
                available,
                openingSessionTarget(
                    selectedSportCount: selected.count,
                    capacityScore: capacityScore
                )
            )
        }

        var counts = Dictionary(uniqueKeysWithValues: selected.map { ($0, 0) })
        var remaining = target

        // Represent every selected sport before adding repeat exposures.
        for sport in selected where remaining > 0 {
            counts[sport, default: 0] += 1
            remaining -= 1
        }

        let ranked = priorities
            .filter { selected.contains($0.sport) }
            .sorted { $0.rank < $1.rank }
            .map(\.sport)
        let defaultOrder: [Sport] = [.swimming, .cycling, .running]
            .filter { selected.contains($0) }
        let order = ranked + defaultOrder.filter { !ranked.contains($0) }

        var cursor = 0
        var stalled = 0
        while remaining > 0, !order.isEmpty {
            let sport = order[cursor % order.count]
            let current = counts[sport, default: 0]
            let limit = perSportOpeningLimit(
                sport,
                experienceScore: experienceScores[sport, default: 0],
                schedule: schedule
            )

            if current < limit {
                counts[sport, default: 0] += 1
                remaining -= 1
                stalled = 0
            } else {
                stalled += 1
                if stalled >= order.count { break }
            }
            cursor += 1
        }

        return selected.compactMap { sport in
            guard let count = counts[sport], count > 0 else { return nil }
            return SportFrequency(sport: sport, sessions: count)
        }
    }

    private static func openingSessionTarget(
        selectedSportCount: Int,
        capacityScore: Double
    ) -> Int {
        switch selectedSportCount {
        case 1:
            if capacityScore < 2 { return 2 }
            if capacityScore < 4 { return 3 }
            return 4
        case 2:
            if capacityScore < 1.5 { return 3 }
            if capacityScore < 3 { return 4 }
            return 5
        default:
            if capacityScore < 1 { return 3 }
            if capacityScore < 2 { return 4 }
            if capacityScore < 3.25 { return 5 }
            return 6
        }
    }

    private static func perSportOpeningLimit(
        _ sport: Sport,
        experienceScore: Int,
        schedule: AthleteSchedule
    ) -> Int {
        if sport == .cycling { return schedule.availableDays.count }
        if sport == .swimming {
            return experienceScore <= 1
                ? min(schedule.availableDays.count, 5)
                : schedule.availableDays.count
        }

        let generalLimit: Int
        switch experienceScore {
        case ...1: generalLimit = 2
        case 2...3: generalLimit = 3
        default: generalLimit = 4
        }

        return sport == .running
            ? min(generalLimit, safeRunningSessions(in: schedule))
            : generalLimit
    }

    private static func runningExperienceScore(_ capability: RunningCapability) -> Int {
        let seconds = capability.currentContinuousSeconds ?? 0
        let distance = max(
            capability.reportedDistanceMeters ?? 0,
            capability.longestRecordedDistanceMeters
        )
        if seconds >= 30 * 60 || distance >= 5_000 { return 4 }
        if seconds >= 20 * 60 || distance >= 3_500 { return 3 }
        if seconds >= 10 * 60 { return 2 }
        if distance > 0 { return 1 }
        return 0
    }

    private static func swimmingExperienceScore(_ capability: SwimmingCapability) -> Int {
        switch capability.currentContinuousMeters ?? 0 {
        case 200...: return 4
        case 100..<200: return 3
        case 50..<100: return 2
        case 25..<50: return 1
        default: return 0
        }
    }

    private static func cyclingExperienceScore(_ capability: CyclingCapability) -> Int {
        switch capability.currentComfortableSeconds {
        case (60 * 60)...: return 4
        case (45 * 60)..<(60 * 60): return 3
        case (30 * 60)..<(45 * 60): return 2
        case (20 * 60)..<(30 * 60): return 1
        default: return 0
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
