import Foundation
import Testing

@testable import TriLoop

@Suite("Training statistics")
struct TrainingStatisticsTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func monday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        return calendar.date(from: components) ?? .now
    }

    private func plan() -> WeeklyPlan {
        SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
    }

    @Test("An untouched week has no statistics")
    func emptyWeekHasNothing() {
        let stats = TrainingStatistics(plans: [plan()], now: monday(), calendar: calendar)

        #expect(stats.hasData == false)
        #expect(stats.sessions == 0)
        #expect(stats.bySport.isEmpty)
        #expect(stats.currentStreakDays == 0)
    }

    @Test("Only reported sessions are counted")
    func unreportedSessionsAreExcluded() {
        let plan = plan()
        let runs = plan.trainingSessions.filter { $0.discipline == .running }
        runs[0].recordCompletion(with: FeedbackDraft(rpe: 3))

        let stats = TrainingStatistics(plans: [plan], now: monday(), calendar: calendar)

        #expect(stats.sessions == 1)
        #expect(stats.bySport.count == 1)
        #expect(stats.bySport.first?.sport == .running)
    }

    @Test("Totals combine time and distance across sports")
    func totalsAreAggregated() {
        let plan = plan()
        for session in plan.trainingSessions {
            session.recordCompletion(with: FeedbackDraft(rpe: 3))
        }

        let stats = TrainingStatistics(plans: [plan], now: monday(), calendar: calendar)

        #expect(stats.sessions == 6)
        #expect(stats.bySport.map(\.sport) == [.running, .swimming, .cycling])
        // Two 28 min runs, two 300 m swims and two 30 min rides.
        #expect(stats.totalDuration == TimeInterval(2 * 1680 + 2 * 1800))
        #expect(stats.totalDistance == 600)
    }

    @Test("Bests reflect the longest session in each sport")
    func bestsArePerSport() {
        let plan = plan()
        for session in plan.trainingSessions {
            session.recordCompletion(with: FeedbackDraft(rpe: 3))
        }

        let stats = TrainingStatistics(plans: [plan], now: monday(), calendar: calendar)

        #expect(stats.longestSwimMeters == 300)
        #expect(stats.longestRideSeconds == TimeInterval(1800))
    }

    @Test("The streak counts consecutive reported days")
    func streakCountsConsecutiveDays() {
        let plan = plan()
        // Monday and Tuesday are consecutive; Thursday is not.
        for session in plan.trainingSessions.prefix(2) {
            session.recordCompletion(with: FeedbackDraft(rpe: 3))
        }

        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday()) ?? monday()
        let stats = TrainingStatistics(plans: [plan], now: tuesday, calendar: calendar)

        #expect(stats.currentStreakDays == 2)
    }

    @Test("A gap ends the streak")
    func gapBreaksTheStreak() {
        let plan = plan()
        plan.trainingSessions[0].recordCompletion(with: FeedbackDraft(rpe: 3))

        // Wednesday: Monday was reported but Tuesday was not.
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday()) ?? monday()
        let stats = TrainingStatistics(plans: [plan], now: wednesday, calendar: calendar)

        #expect(stats.currentStreakDays == 0)
    }
}
