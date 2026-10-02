import Foundation
import Testing

@testable import Athevia

@Suite("Weekly training frequency")
struct WeeklyTrainingFrequencyPolicyTests {
    private let policy = WeeklyTrainingFrequencyPolicy()

    private func plan(sessionCount: Int) -> WeeklyPlan {
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let workouts = (0..<sessionCount).map { index in
            PlannedWorkout(
                date: start.addingTimeInterval(TimeInterval(index * 24 * 60 * 60)),
                discipline: .running,
                title: "Run"
            )
        }
        return WeeklyPlan(
            weekNumber: 1,
            startDate: start,
            endDate: start.addingTimeInterval(6 * 24 * 60 * 60),
            workouts: workouts
        )
    }

    private func analysis(
        planned: Int,
        completed: Int,
        skipped: Int = 0,
        status: AssessmentStatus = .progress,
        pain: Int = 0,
        rpe: Double = 4
    ) -> WeeklyAnalysis {
        WeeklyAnalysis(
            weekNumber: 1,
            startDate: .now,
            endDate: .now,
            plannedSessions: planned,
            completedSessions: completed,
            skippedSessions: skipped,
            sports: [
                SportAnalysis(
                    sport: .running,
                    status: status,
                    plannedSessions: planned,
                    completedSessions: completed,
                    averageRPE: rpe,
                    highestPain: pain,
                    totalDurationSeconds: 0,
                    totalDistanceMeters: 0,
                    reasons: [],
                    adjustment: .hold
                )
            ]
        )
    }

    @Test("Opening week respects two and three day targets")
    func openingTwoAndThree() {
        #expect(policy.openingTarget(requested: 2, selectedSportCount: 1, availableDays: 7) == 2)
        #expect(policy.openingTarget(requested: 3, selectedSportCount: 1, availableDays: 7) == 3)
    }

    @Test("Four and five day targets both open at three")
    func higherTargetsOpenAtThree() {
        #expect(policy.openingTarget(requested: 4, selectedSportCount: 1, availableDays: 7) == 3)
        #expect(policy.openingTarget(requested: 5, selectedSportCount: 1, availableDays: 7) == 3)
    }

    @Test("A clean week adds at most one training day")
    func cleanWeekAddsOneDay() {
        let previous = plan(sessionCount: 3)
        let review = analysis(planned: 3, completed: 3)

        #expect(
            policy.nextTarget(
                requested: 5,
                selectedSportCount: 1,
                availableDays: 7,
                previousPlan: previous,
                analysis: review
            ) == 4
        )
    }

    @Test("Five day target reaches five only after another clean week")
    func fiveRequiresSecondStep() {
        let previous = plan(sessionCount: 4)
        let review = analysis(planned: 4, completed: 4)

        #expect(
            policy.nextTarget(
                requested: 5,
                selectedSportCount: 1,
                availableDays: 7,
                previousPlan: previous,
                analysis: review
            ) == 5
        )
    }

    @Test("Incomplete or recovery flagged weeks do not add a day")
    func unsafeWeekHoldsFrequency() {
        let previous = plan(sessionCount: 3)

        let incomplete = analysis(planned: 3, completed: 2)
        #expect(
            policy.nextTarget(
                requested: 4,
                selectedSportCount: 1,
                availableDays: 7,
                previousPlan: previous,
                analysis: incomplete
            ) == 3
        )

        let recovery = analysis(
            planned: 3,
            completed: 3,
            status: .recoveryRequired,
            pain: 5
        )
        #expect(
            policy.nextTarget(
                requested: 4,
                selectedSportCount: 1,
                availableDays: 7,
                previousPlan: previous,
                analysis: recovery
            ) == 3
        )
    }
}
