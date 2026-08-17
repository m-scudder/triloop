import Foundation

/// When each sport becomes part of the plan.
///
/// Equipment and intent arrive on real dates: a bike turns up on a Thursday,
/// swimming starts when the athlete decides. Rather than hand-editing weeks, the
/// generator asks what is available for the week it is building.
struct SportAvailability: Equatable, Sendable {
    var availableFrom: [Sport: Date]

    func isAvailable(_ sport: Sport, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let start = availableFrom[sport] else { return true }
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: start)
    }
}

extension SportAvailability {
    static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? .distantPast
    }

    /// The athlete's actual start dates: the bike arrives Thursday 20 August, so
    /// riding begins the day after; swimming is deferred to mid-September.
    static func athlete(calendar: Calendar = .current) -> SportAvailability {
        SportAvailability(
            availableFrom: [
                .cycling: date(2026, 8, 21, calendar: calendar),
                .swimming: date(2026, 9, 14, calendar: calendar)
            ]
        )
    }

    static let everything = SportAvailability(availableFrom: [:])
}
