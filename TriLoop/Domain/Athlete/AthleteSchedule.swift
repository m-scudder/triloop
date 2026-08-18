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
}

/// What the athlete *can* do on one weekday.
///
/// Permission, not instruction: an available day may still end up as rest. The
/// scheduler decides what to place, this only bounds what it may consider.
struct TrainingAvailability: Codable, Equatable, Sendable {
    var weekday: Weekday
    var sports: Set<Sport>
    /// Longest session that fits that day. `nil` means no stated limit.
    var maxDurationMinutes: Int?

    init(weekday: Weekday, sports: Set<Sport> = [], maxDurationMinutes: Int? = nil) {
        self.weekday = weekday
        self.sports = sports
        self.maxDurationMinutes = maxDurationMinutes
    }

    var isAvailable: Bool { !sports.isEmpty }

    func allows(_ sport: Sport) -> Bool { sports.contains(sport) }

    /// Whether a session of this length fits. An unstated limit allows anything.
    func accommodates(seconds: TimeInterval?) -> Bool {
        guard let maxDurationMinutes, let seconds else { return true }
        return seconds <= TimeInterval(maxDurationMinutes * 60)
    }
}

/// The athlete's whole week of availability.
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

    func availability(on weekday: Weekday) -> TrainingAvailability {
        days.first { $0.weekday == weekday } ?? TrainingAvailability(weekday: weekday)
    }

    func allows(_ sport: Sport, on weekday: Weekday) -> Bool {
        availability(on: weekday).allows(sport)
    }

    var availableDays: [TrainingAvailability] {
        Weekday.trainingWeek
            .map(availability(on:))
            .filter(\.isAvailable)
    }

    /// Every sport the athlete can train at least once a week.
    var trainableSports: Set<Sport> {
        availableDays.reduce(into: Set<Sport>()) { $0.formUnion($1.sports) }
    }

    /// Two available days is the least that can carry a week with any recovery
    /// spacing at all. Below that there is no plan worth generating.
    var isUsable: Bool { availableDays.count >= 2 }
}
