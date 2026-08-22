import Foundation
import Testing
@testable import TriLoop

/// The rule that decides whether onboarding offers "start this week".
///
/// Availability, not the weekday number: the bug this replaces refused a Friday
/// start for an athlete whose Friday was their last training day.
@MainActor
@Suite("Onboarding start choice")
struct OnboardingStartChoiceTests {

    private let calendar = Calendar.current

    /// Monday 5 January 2026 through the Sunday, in local time.
    private func date(_ weekday: Weekday) -> Date {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? .now
        return calendar.date(byAdding: .day, value: weekday.offsetFromMonday, to: monday) ?? monday
    }

    private func schedule(training days: [Weekday]) -> AthleteSchedule {
        AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(weekday: $0, isAvailable: days.contains($0))
            }
        )
    }

    private func canStart(_ schedule: AthleteSchedule, on weekday: Weekday) -> Bool {
        OnboardingModel.hasTrainingDayLeft(in: schedule, on: date(weekday), calendar: calendar)
    }

    @Test("The fixture really does run Monday to Sunday")
    func fixtureIsAnchoredCorrectly() {
        for weekday in Weekday.trainingWeek {
            #expect(Weekday(date: date(weekday), calendar: calendar) == weekday)
        }
    }

    @Test("A weekday athlete can still start on their last training day")
    func fridayStartWithRestingWeekend() {
        let weekdaysOnly = schedule(training: [.monday, .tuesday, .wednesday, .thursday, .friday])

        #expect(canStart(weekdaysOnly, on: .friday))
    }

    @Test("Once every training day has passed, the week has nothing left to offer")
    func weekendAfterWeekdayTraining() {
        let weekdaysOnly = schedule(training: [.monday, .tuesday, .wednesday, .thursday, .friday])

        #expect(!canStart(weekdaysOnly, on: .saturday))
        #expect(!canStart(weekdaysOnly, on: .sunday))
    }

    @Test("An athlete who trains at weekends can start on the Saturday")
    func weekendTrainer() {
        let weekendOnly = schedule(training: [.saturday, .sunday])

        #expect(canStart(weekendOnly, on: .friday))
        #expect(canStart(weekendOnly, on: .saturday))
        #expect(canStart(weekendOnly, on: .sunday))
    }

    @Test("Today counts as a day still available")
    func todayIsIncluded() {
        #expect(canStart(schedule(training: [.wednesday]), on: .wednesday))
        #expect(!canStart(schedule(training: [.wednesday]), on: .thursday))
    }

    @Test("A schedule with nothing available cannot start at all")
    func noAvailability() {
        #expect(!canStart(schedule(training: []), on: .monday))
    }
}
