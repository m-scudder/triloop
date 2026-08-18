import Foundation
import SwiftData
import Testing

@testable import TriLoop

@Suite("Plan reshaping")
@MainActor
struct PlanReshaperTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Monday 24 August 2026.
    private func monday() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 24)) ?? .now
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday()) ?? monday()
    }

    private func reshaper() -> PlanReshaper {
        PlanReshaper(calendar: calendar)
    }

    private func plan() -> WeeklyPlan {
        SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
    }

    private func schedule(_ available: Set<Weekday>) -> AthleteSchedule {
        AthleteSchedule(
            days: Weekday.trainingWeek.map {
                TrainingAvailability(weekday: $0, isAvailable: available.contains($0))
            }
        )
    }

    private let preferences = [
        SportPreference(sport: .running, sessionsPerWeek: 2, typicalMinutes: 45),
        SportPreference(sport: .swimming, sessionsPerWeek: 2, typicalMinutes: 45),
        SportPreference(sport: .cycling, sessionsPerWeek: 2, typicalMinutes: 45)
    ]

    @Test("A completed session is never moved")
    func completedSessionsNeverMove() throws {
        let week = plan()
        let first = try #require(week.orderedWorkouts.first)
        first.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))

        let outcome = reshaper().reshape(
            week,
            schedule: schedule([.thursday, .friday, .saturday]),
            preferences: preferences,
            asOf: monday()
        )

        #expect(outcome.changes.contains { calendar.isDate($0.date, inSameDayAs: self.monday()) } == false)
        #expect(first.hasReport)
    }

    @Test("A skipped session stays skipped")
    func skippedSessionsStaySkipped() {
        let week = plan()
        let tuesday = week.orderedWorkouts.first { calendar.isDate($0.date, inSameDayAs: day(1)) }
        tuesday?.skip()

        let outcome = reshaper().reshape(
            week,
            schedule: schedule([.thursday, .friday]),
            preferences: preferences,
            asOf: monday()
        )

        #expect(outcome.changes.contains { calendar.isDate($0.date, inSameDayAs: self.day(1)) } == false)
        #expect(tuesday?.isSkipped == true)
    }

    @Test("Days already gone are left as history")
    func pastDaysAreUntouched() {
        let week = plan()

        // Reshaping on the Thursday: Monday to Wednesday are history.
        let outcome = reshaper().reshape(
            week,
            schedule: schedule([.monday, .tuesday, .wednesday]),
            preferences: preferences,
            asOf: day(3)
        )

        for change in outcome.changes {
            #expect(change.date >= self.day(3))
        }
    }

    @Test("A future session moves to a day the athlete can train")
    func futureSessionsMove() {
        let week = plan()

        let outcome = reshaper().reshape(
            week,
            schedule: schedule([.monday, .tuesday, .wednesday]),
            preferences: preferences,
            asOf: monday()
        )

        // Thursday onwards is no longer available, so nothing survives there.
        #expect(outcome.isUnchanged == false)
        for change in outcome.changes where change.date >= self.day(3) {
            #expect(change.discipline == .rest)
        }
    }

    @Test("Reshaping against an unchanged schedule changes nothing")
    func matchingScheduleIsANoOp() {
        let week = plan()
        let everyDay = AthleteSchedule.everyDay()

        let outcome = reshaper().reshape(
            week,
            schedule: everyDay,
            preferences: preferences,
            asOf: monday()
        )

        // The seed already places six sessions across seven days.
        #expect(outcome.dropped == 0)
    }

    @Test("A fully reported week has nothing left to reshape")
    func reportedWeekIsUntouched() {
        let week = plan()
        for session in week.trainingSessions {
            session.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        }

        let outcome = reshaper().reshape(
            week,
            schedule: schedule([.monday]),
            preferences: preferences,
            asOf: monday()
        )

        #expect(outcome.changes.allSatisfy { change in
            week.workout(on: change.date, calendar: calendar)?.hasReport != true
        })
    }

    @Test("A week entirely in the past is never rewritten")
    func historicalWeekIsNeverRewritten() {
        let week = plan()

        let outcome = reshaper().reshape(
            week,
            schedule: schedule([.monday, .tuesday]),
            preferences: preferences,
            asOf: day(30)
        )

        #expect(outcome.isUnchanged)
        #expect(outcome.preserved == 7)
    }

    @Test("Sessions that no longer fit are reported rather than lost quietly")
    func droppedSessionsAreReported() {
        let week = plan()

        let outcome = reshaper().reshape(
            week,
            schedule: schedule([.monday]),
            preferences: preferences,
            asOf: monday()
        )

        #expect(outcome.dropped > 0)
    }

    @Test("Applying a reshape records why the week changed")
    func reshapeRecordsItsReason() throws {
        let container = try TriLoopModelContainer.make(inMemory: true)
        let context = container.mainContext

        let week = plan()
        context.insert(week)

        let profile = AthleteProfile(
            name: "Athlete",
            trainingStartDate: monday(),
            setup: AthleteSetup(
                schedule: schedule([.monday, .tuesday, .wednesday]),
                preferences: preferences,
                stage: .complete,
                completedAt: .now
            )
        )
        context.insert(profile)
        try context.save()

        var store = PlanStore(context: context)
        store.reshaper = reshaper()
        let outcome = store.reshapeWeek(week, asOf: monday())

        #expect(outcome.isUnchanged == false)
        #expect(week.generationReasonCode == .availabilityChanged)
        #expect(week.orderedWorkouts.count == 7)
    }
}
