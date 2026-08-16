import Foundation

extension Collection where Element == WeeklyPlan {
    /// The week the athlete is actually in.
    ///
    /// Sorting by start date is not enough once a future week has been
    /// generated: the newest plan is next week, not the current one.
    func currentPlan(on date: Date = .now, calendar: Calendar = .current) -> WeeklyPlan? {
        if let containing = first(where: { $0.contains(date, calendar: calendar) }) {
            return containing
        }
        if let latestStarted = filter({ $0.startDate <= date }).max(by: { $0.startDate < $1.startDate }) {
            return latestStarted
        }
        return self.min { $0.startDate < $1.startDate }
    }
}
