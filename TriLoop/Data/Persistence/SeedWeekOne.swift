import Foundation

/// Development seed for the athlete's actual first training week.
///
/// The dates are data, not architecture: `startDate` is injectable so the
/// Phase 4 generator and tests can build weeks anywhere on the calendar.
enum SeedWeekOne {

    /// Monday 17 August 2026, in the current calendar's time zone.
    static func defaultStartDate(calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        return calendar.date(from: components) ?? calendar.startOfDay(for: .now)
    }

    static func makeProfile(startDate: Date) -> AthleteProfile {
        AthleteProfile(
            name: "Athlete",
            experienceLevel: .beginner,
            trainingStartDate: startDate
        )
    }

    /// A fixed three-sport week, for previews, tests and Developer tools.
    ///
    /// No availability input: a real athlete's week is planned from their own
    /// schedule by `FirstWeekBuilder`. This exists only to give the rest of the
    /// app something predictable to render.
    static let disciplines: [Discipline] = [
        .running, .swimming, .cycling, .running, .swimming, .cycling, .rest
    ]

    static func makePlan(
        startDate: Date? = nil,
        calendar: Calendar = .current
    ) -> WeeklyPlan {
        let monday = calendar.startOfDay(for: startDate ?? defaultStartDate(calendar: calendar))
        let parameters = TrainingParameters()

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        }

        let workouts = disciplines.enumerated().map { offset, discipline in
            WorkoutTemplates.session(discipline, on: day(offset), parameters: parameters)
        }

        return WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: day(disciplines.count - 1),
            status: .active,
            generationReason: "Fixed development week across all three sports.",
            parameters: parameters,
            workouts: workouts
        )
    }

}
