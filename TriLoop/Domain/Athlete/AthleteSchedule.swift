import Foundation

/// A day of the week, independent of locale.
///
/// `Calendar` numbers weekdays from Sunday and its `firstWeekday` varies by
/// region, which has already caused one bug in the day strip. Training weeks
/// here always run Monday to Sunday.
enum Weekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    /// Monday first, whatever the locale says.
    static var trainingWeek: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.offsetFromMonday < rhs.offsetFromMonday
    }

    /// 0 for Monday through 6 for Sunday.
    var offsetFromMonday: Int {
        rawValue == 1 ? 6 : rawValue - 2
    }

    init?(date: Date, calendar: Calendar = .current) {
        self.init(rawValue: calendar.component(.weekday, from: date))
    }

    var displayName: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    var shortName: String { String(displayName.prefix(3)) }

    var initial: String { String(displayName.prefix(1)) }
}

/// Whether the athlete can train on one weekday, and for how long.
///
/// Deliberately not per-sport: which sport lands where is the planner's job,
/// and a twenty-one-cell grid asked more of the athlete than it was worth.
struct TrainingAvailability: Codable, Equatable, Sendable {
    var weekday: Weekday
    var isAvailable: Bool
    /// Longest session that fits that day. `nil` means no stated limit.
    var maxDurationMinutes: Int?

    init(weekday: Weekday, isAvailable: Bool = false, maxDurationMinutes: Int? = nil) {
        self.weekday = weekday
        self.isAvailable = isAvailable
        self.maxDurationMinutes = maxDurationMinutes
    }

    /// Whether a session of this length fits. An unstated limit allows anything.
    func accommodates(seconds: TimeInterval?) -> Bool {
        guard let maxDurationMinutes, let seconds else { return true }
        return seconds <= TimeInterval(maxDurationMinutes * 60)
    }

    /// Decoded key by key so a schedule stored by an earlier build still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
        }

        weekday = value(.weekday, Weekday.monday)
        isAvailable = value(.isAvailable, false)
        maxDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .maxDurationMinutes)) ?? nil
    }
}

/// The days the athlete can train, and by omission the days they rest.
struct AthleteSchedule: Codable, Equatable, Sendable {
    var days: [TrainingAvailability]

    init(days: [TrainingAvailability] = []) {
        self.days = days
    }

    /// Nothing available. The starting point for onboarding, and never a valid
    /// finishing point — `isUsable` is what gates plan generation.
    static var empty: AthleteSchedule {
        AthleteSchedule(days: Weekday.trainingWeek.map { TrainingAvailability(weekday: $0) })
    }

    /// Every day open. For previews and tests about something other than
    /// availability.
    static func everyDay(maxDurationMinutes: Int? = nil) -> AthleteSchedule {
        AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(weekday: $0, isAvailable: true, maxDurationMinutes: maxDurationMinutes)
            }
        )
    }

    func availability(on weekday: Weekday) -> TrainingAvailability {
        days.first { $0.weekday == weekday } ?? TrainingAvailability(weekday: weekday)
    }

    func isAvailable(on weekday: Weekday) -> Bool {
        availability(on: weekday).isAvailable
    }

    var availableDays: [TrainingAvailability] {
        Weekday.trainingWeek
            .map(availability(on:))
            .filter(\.isAvailable)
    }

    var restDays: [Weekday] {
        Weekday.trainingWeek.filter { !isAvailable(on: $0) }
    }

    /// Two available days is the least that can carry a week with any recovery
    /// spacing at all. Below that there is no plan worth generating.
    var isUsable: Bool { availableDays.count >= 2 }
}
