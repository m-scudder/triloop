import Foundation

extension Collection where Element == WeeklyPlan {
    /// The week the athlete is actually in.
    ///
    /// Sorting by start date is not enough once a future week has been
    /// generated: the newest plan is next week, not the current one.
    func currentPlan(on date: Date = .now, calendar: Calendar = .current) -> WeeklyPlan? {
        let active = filter { $0.status == .active }

        if let containing = active.first(where: { $0.contains(date, calendar: calendar) }) {
            return containing
        }
        // A completed week has finished early through reports or simulation;
        // move straight to the active successor instead of showing stale work.
        if let next = active.min(by: { $0.startDate < $1.startDate }) {
            return next
        }
        if let latestStarted = filter({ $0.startDate <= date }).max(by: { $0.startDate < $1.startDate }) {
            return latestStarted
        }
        return self.min { $0.startDate < $1.startDate }
    }
}
