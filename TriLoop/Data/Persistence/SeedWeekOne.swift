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

    static func makePlan(
        startDate: Date? = nil,
        calendar: Calendar = .current
    ) -> WeeklyPlan {
        let monday = calendar.startOfDay(for: startDate ?? defaultStartDate(calendar: calendar))
        let parameters = TrainingParameters()

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        }

        let workouts: [PlannedWorkout] = [
            WorkoutTemplates.runWalk(on: day(0), sessionNumber: 1, parameters: parameters),
            WorkoutTemplates.techniqueSwim(on: day(1), sessionNumber: 1, parameters: parameters),
            WorkoutTemplates.recoveryDay(
                on: day(2),
                goal: "Let the first run and swim settle before repeating them."
            ),
            WorkoutTemplates.runWalk(on: day(3), sessionNumber: 2, parameters: parameters),
            WorkoutTemplates.techniqueSwim(on: day(4), sessionNumber: 2, parameters: parameters),
            WorkoutTemplates.easyRide(
                on: day(5),
                parameters: parameters,
                goal: "First ride on the new bike. Get used to handling, position and gearing."
            ),
            WorkoutTemplates.restDay(on: day(6))
        ]

        return WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: day(6),
            status: .active,
            generationReason: "First week. Introductory volume across all three sports, with cycling starting Saturday.",
            parameters: parameters,
            workouts: workouts
        )
    }

}
