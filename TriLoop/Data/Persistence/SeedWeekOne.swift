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
        calendar: Calendar = .current,
        availability: SportAvailability? = nil
    ) -> WeeklyPlan {
        let monday = calendar.startOfDay(for: startDate ?? defaultStartDate(calendar: calendar))
        let parameters = TrainingParameters()
        let schedule = WeeklySchedule.forWeek(
            starting: monday,
            availability: availability ?? .athlete(calendar: calendar),
            calendar: calendar
        )

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        }

        let workouts = schedule.disciplines.enumerated().map { offset, discipline in
            WorkoutTemplates.session(discipline, on: day(offset), parameters: parameters)
        }

        return WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: day(schedule.disciplines.count - 1),
            status: .active,
            generationReason: "First week. Running while the bike arrives, then two easy rides to finish.",
            parameters: parameters,
            workouts: workouts
        )
    }

}
