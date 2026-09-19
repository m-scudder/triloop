import Foundation

enum TrainingFormatter {

    /// "28 min", "1 hr 5 min" — for totals shown in lists and headers.
    static func totalDuration(seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    /// "1:00", "1:15", "20:00" — for individual interval steps.
    static func intervalDuration(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "300 m", "1.2 km".
    static func distance(meters: Double) -> String {
        guard meters >= 1000 else { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    /// "1:52 / 100 m" without the suffix — swimmers compare on this unit.
    static func swimPace(secondsPer100m: Double) -> String {
        let total = Int(secondsPer100m.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func rpe(_ range: RPERange) -> String {
        range.isExact ? "\(range.lower) / 10" : "\(range.lower)–\(range.upper) / 10"
    }

    static func weekRange(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let startFormat: Date.FormatStyle = sameMonth
            ? .dateTime.day()
            : .dateTime.day().month(.abbreviated)
        return "\(start.formatted(startFormat)) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    static func weekdayAbbreviation(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func weekdayInitial(for date: Date) -> String {
        String(date.formatted(.dateTime.weekday(.narrow)).prefix(1))
    }
}
