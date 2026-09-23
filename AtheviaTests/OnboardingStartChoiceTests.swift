import Foundation
import Testing
@testable import Athevia

@MainActor
@Suite("Onboarding start date")
struct OnboardingStartChoiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(year: Int = 2026, month: Int = 1, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    private func schedule(training days: [Weekday]) -> AthleteSchedule {
        AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(weekday: $0, isAvailable: days.contains($0))
            }
        )
    }

    @Test("Selected date is kept when a training day remains in that week")
    func requestedDateIsUsed() {
        let friday = date(day: 9)
        let result = OnboardingModel.effectiveStartDate(
            requested: friday,
            schedule: schedule(training: [.friday, .sunday]),
            calendar: calendar
        )

        #expect(result == friday)
    }

    @Test("Late-week start rolls to Monday when no training day remains")
    func lateWeekStartMovesToNextMonday() {
        let saturday = date(day: 10)
        let monday = date(day: 12)

        let result = OnboardingModel.effectiveStartDate(
            requested: saturday,
            schedule: schedule(training: [.monday, .wednesday, .friday]),
            calendar: calendar
        )

        #expect(result == monday)
    }

    @Test("Sunday remains valid when Sunday is available")
    func sundayCanBeSelected() {
        let sunday = date(day: 11)

        let result = OnboardingModel.effectiveStartDate(
            requested: sunday,
            schedule: schedule(training: [.wednesday, .sunday]),
            calendar: calendar
        )

        #expect(result == sunday)
    }

    @Test("A Monday request stays Monday")
    func mondayRequestStaysMonday() {
        let monday = date(day: 12)

        let result = OnboardingModel.effectiveStartDate(
            requested: monday,
            schedule: schedule(training: [.tuesday, .thursday]),
            calendar: calendar
        )

        #expect(result == monday)
    }
}
