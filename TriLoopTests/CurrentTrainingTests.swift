import Foundation
import Testing

@testable import TriLoop

@Suite("Current training summary")
struct CurrentTrainingTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func monday() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 17)) ?? .now
    }

    private func plan() -> WeeklyPlan {
        SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
    }

    @Test("No plans means no summary")
    func emptyPlansGiveNothing() {
        #expect(CurrentTraining(plans: []) == nil)
    }

    @Test("Only sports actually prescribed appear")
    func onlyPrescribedSportsAppear() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let summary = try #require(CurrentTraining(plans: [plan]))

        // The fixture carries all three sports.
        #expect(summary.states.map(\.sport) == [.running, .swimming, .cycling])
    }

    @Test("A sport missing from the week is not reported")
    func absentSportIsOmitted() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        for swim in plan.orderedWorkouts where swim.discipline == .swimming {
            plan.workouts.removeAll { $0 === swim }
        }

        let summary = try #require(CurrentTraining(plans: [plan]))

        #expect(summary.states.map(\.sport) == [.running, .cycling])
    }

    @Test("Interval running reads as its prescription")
    func intervalRunningIsDescribed() throws {
        let summary = try #require(CurrentTraining(plans: [plan()]))
        let running = try #require(summary.states.first { $0.sport == .running })

        #expect(running.prescription == "6 × 1:00 run / 2:00 walk")
    }

    @Test("Continuous running is described as continuous")
    func continuousRunningIsDescribed() throws {
        let plan = plan()
        plan.parameters.runIsContinuous = true
        plan.parameters.runContinuousSeconds = 900

        let summary = try #require(CurrentTraining(plans: [plan]))
        let running = try #require(summary.states.first { $0.sport == .running })

        #expect(running.prescription == "15 min continuous")
    }

    @Test("Swimming shows volume and rest together")
    func swimmingShowsRest() throws {
        let summary = try #require(CurrentTraining(plans: [plan()]))
        let swimming = try #require(summary.states.first { $0.sport == .swimming })

        #expect(swimming.prescription == "300 m · 45s rest")
    }

    @Test("Direction is absent until a week has been reported on")
    func directionNeedsReports() throws {
        let summary = try #require(CurrentTraining(plans: [plan()]))

        #expect(summary.states.allSatisfy { $0.status == nil })
    }

    @Test("Direction comes from the most recent reported week")
    func directionFollowsTheLastReport() throws {
        let plan = plan()
        for session in plan.trainingSessions {
            session.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        }

        let summary = try #require(CurrentTraining(plans: [plan]))

        #expect(summary.states.allSatisfy { $0.status == .progress })
    }
}
