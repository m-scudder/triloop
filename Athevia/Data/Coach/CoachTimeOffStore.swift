import Foundation

struct CoachTimeOffRange: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let createdAt: Date

    init(id: UUID = UUID(), start: Date, end: Date, createdAt: Date = .now) {
        self.id = id
        self.start = start
        self.end = end
        self.createdAt = createdAt
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: start)
            && day <= calendar.startOfDay(for: end)
    }
}

/// Athlete-scoped temporary availability overrides. These are deliberately
/// separate from the recurring AthleteSchedule: a holiday should expire rather
/// than silently changing every future Monday/Tuesday/etc.
struct CoachTimeOffStore {
    private let defaults: UserDefaults
    private let key: String

    init(athleteScopeID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "athevia.coach-time-off.v1.\(athleteScopeID)"
    }

    func ranges(asOf now: Date = .now, calendar: Calendar = .current) -> [CoachTimeOffRange] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let values = try? decoder.decode([CoachTimeOffRange].self, from: data) else {
            return []
        }
        return values.filter {
            calendar.startOfDay(for: $0.end) >= calendar.startOfDay(for: now)
        }
    }

    @discardableResult
    func record(
        start: Date,
        end: Date,
        at createdAt: Date = .now,
        calendar: Calendar = .current
    ) -> CoachTimeOffRange? {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard last >= first else { return nil }

        var values = ranges(asOf: first, calendar: calendar)
        let range = CoachTimeOffRange(start: first, end: last, createdAt: createdAt)
        values.append(range)
        save(values)
        return range
    }

    func schedule(
        from base: AthleteSchedule,
        weekStarting start: Date,
        calendar: Calendar = .current
    ) -> AthleteSchedule {
        let active = ranges(asOf: start, calendar: calendar)
        guard !active.isEmpty else { return base }

        var schedule = base
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                  active.contains(where: { $0.contains(date, calendar: calendar) }),
                  let weekday = Weekday(date: date, calendar: calendar) else {
                continue
            }
            if let index = schedule.days.firstIndex(where: { $0.weekday == weekday }) {
                schedule.days[index].isAvailable = false
            } else {
                schedule.days.append(TrainingAvailability(weekday: weekday, isAvailable: false))
            }
        }
        return schedule
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ values: [CoachTimeOffRange]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(values) else { return }
        defaults.set(data, forKey: key)
    }
}
