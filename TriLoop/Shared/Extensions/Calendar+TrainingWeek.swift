import Foundation

extension Calendar {
    /// 1-based day index of `date` within a plan starting on `startDate`.
    func trainingDayNumber(for date: Date, planStart startDate: Date) -> Int {
        let days = dateComponents([.day], from: startOfDay(for: startDate), to: startOfDay(for: date)).day ?? 0
        return days + 1
    }
}
