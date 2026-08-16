import Foundation

/// What the Today screen should lead with.
///
/// Pure value logic, deliberately kept out of the view so it can be tested and
/// so it behaves sensibly before the plan starts or after it ends.
struct TodayFocus: Equatable {
    enum Kind: Equatable {
        case today
        case upcoming
        case weekComplete
    }

    let kind: Kind
    let workoutID: UUID?
    let dayNumber: Int?

    static let weekComplete = TodayFocus(kind: .weekComplete, workoutID: nil, dayNumber: nil)

    static func resolve(
        plan: WeeklyPlan,
        date: Date = .now,
        calendar: Calendar = .current
    ) -> TodayFocus {
        let today = calendar.startOfDay(for: date)

        if let workout = plan.workout(on: today, calendar: calendar) {
            return TodayFocus(
                kind: .today,
                workoutID: workout.id,
                dayNumber: calendar.trainingDayNumber(for: workout.date, planStart: plan.startDate)
            )
        }

        if let next = plan.orderedWorkouts.first(where: { calendar.startOfDay(for: $0.date) > today }) {
            return TodayFocus(
                kind: .upcoming,
                workoutID: next.id,
                dayNumber: calendar.trainingDayNumber(for: next.date, planStart: plan.startDate)
            )
        }

        return .weekComplete
    }
}

enum Greeting {
    static func text(at date: Date = .now, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 0..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
