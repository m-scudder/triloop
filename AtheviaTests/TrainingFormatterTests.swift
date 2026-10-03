import Foundation
import Testing

@testable import Athevia

struct TrainingFormatterTests {

    @Test func formatsTotalsInMinutesAndHours() {
        #expect(TrainingFormatter.totalDuration(seconds: 28 * 60) == "28 min")
        #expect(TrainingFormatter.totalDuration(seconds: 60 * 60) == "1 hr")
        #expect(TrainingFormatter.totalDuration(seconds: 65 * 60) == "1 hr 5 min")
    }

    @Test func formatsIntervalsAsMinutesAndSeconds() {
        #expect(TrainingFormatter.intervalDuration(seconds: 60) == "1:00")
        #expect(TrainingFormatter.intervalDuration(seconds: 75) == "1:15")
        #expect(TrainingFormatter.intervalDuration(seconds: 1200) == "20:00")
    }

    @Test func formatsDistanceInMetresThenKilometres() {
        #expect(TrainingFormatter.distance(meters: 300) == "300 m")
        #expect(TrainingFormatter.distance(meters: 1200) == "1.2 km")
    }

    @Test func pickerDateUsesDayTextMonthAndFourDigitYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(
            TimeZone(secondsFromGMT: 0)
        )
        let date = try #require(
            calendar.date(
                from: DateComponents(
                    year: 1995,
                    month: 12,
                    day: 13
                )
            )
        )

        #expect(
            TrainingFormatter.pickerDate(
                date,
                calendar: calendar
            ) == "13/Dec/1995"
        )
    }

    @Test func rpeRangeIsClampedToTheScale() {
        #expect(RPERange(0, 12) == RPERange(1, 10))
        #expect(RPERange(7, 3).upper == 7)
        #expect(RPERange(4).isExact)
    }

    @Test func rpeRangeFormatting() {
        #expect(TrainingFormatter.rpe(RPERange(3, 4)) == "3–4 / 10")
        #expect(TrainingFormatter.rpe(RPERange(5)) == "5 / 10")
    }
}
