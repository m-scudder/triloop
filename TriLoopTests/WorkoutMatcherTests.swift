import Foundation
import Testing

@testable import TriLoop

@Suite("Workout matching")
struct WorkoutMatcherTests {

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

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let start = calendar.date(byAdding: .day, value: offset, to: monday()) ?? monday()
        return calendar.date(byAdding: .hour, value: hour, to: start) ?? start
    }

    private func activity(
        _ sport: Sport,
        at date: Date,
        duration: TimeInterval = 1680,
        distance: Double? = nil
    ) -> ImportedWorkout {
        ImportedWorkout(
            healthKitUUID: UUID(),
            sport: sport,
            startDate: date,
            endDate: date.addingTimeInterval(duration),
            duration: duration,
            distanceMeters: distance
        )
    }

    private func plan() -> WeeklyPlan {
        SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
    }

    private func matcher(toleranceDays: Int = 1) -> WorkoutMatcher {
        WorkoutMatcher(calendar: calendar, toleranceDays: toleranceDays)
    }

    @Test("A run on the planned day matches that session")
    func sameDayMatch() {
        let plan = plan()
        let result = matcher().match(
            planned: plan.orderedWorkouts,
            with: [activity(.running, at: day(0))]
        )

        #expect(result.matches.count == 1)
        #expect(result.matches.first?.planned.discipline == .running)
        #expect(result.matches.first?.dayOffset == 0)
        #expect(result.unmatchedImported.isEmpty)
    }

    @Test("A different sport never matches")
    func sportMustAgree() {
        let plan = plan()
        let result = matcher().match(
            planned: plan.orderedWorkouts,
            with: [activity(.cycling, at: day(0))]
        )

        #expect(result.matches.isEmpty)
        #expect(result.unmatchedImported.count == 1)
    }

    @Test("Rest and recovery days are never matched")
    func restDaysAreIgnored() {
        let plan = plan()
        let result = matcher().match(
            planned: plan.orderedWorkouts,
            with: [activity(.running, at: day(2))]
        )

        #expect(result.matches.allSatisfy { $0.planned.discipline.isTrainingSession })
        #expect(result.unmatchedPlanned.allSatisfy { $0.discipline.isTrainingSession })
    }

    @Test("Each activity is claimed by at most one session")
    func matchingIsOneToOne() {
        let plan = plan()
        let result = matcher().match(
            planned: plan.orderedWorkouts,
            with: [
                activity(.running, at: day(0, hour: 7)),
                activity(.running, at: day(0, hour: 18))
            ]
        )

        #expect(result.matches.count == 1)
        #expect(result.unmatchedImported.count == 1)
        #expect(result.matches.first?.imported.startDate == day(0, hour: 7))
    }

    @Test("A session done the next day still counts")
    func toleranceAllowsSlippage() {
        let plan = plan()
        let result = matcher().match(
            planned: plan.orderedWorkouts,
            with: [activity(.swimming, at: day(2))]
        )

        #expect(result.matches.count == 1)
        #expect(result.matches.first?.dayOffset == 1)
    }

    @Test("Nothing matches outside the tolerance window")
    func beyondToleranceIsUnmatched() {
        let plan = plan()
        let result = matcher(toleranceDays: 0).match(
            planned: plan.orderedWorkouts,
            with: [activity(.swimming, at: day(2))]
        )

        #expect(result.matches.isEmpty)
        #expect(result.unmatchedImported.count == 1)
    }

    @Test("A full week of training matches every session")
    func aFullWeekMatches() {
        let plan = plan()
        let result = matcher().match(
            planned: plan.orderedWorkouts,
            with: [
                activity(.running, at: day(0)),
                activity(.swimming, at: day(1), distance: 300),
                activity(.cycling, at: day(2), duration: 1800),
                activity(.running, at: day(3)),
                activity(.swimming, at: day(4), distance: 300),
                activity(.cycling, at: day(5), duration: 1800)
            ]
        )

        #expect(result.matches.count == 6)
        #expect(result.unmatchedPlanned.isEmpty)
        #expect(result.unmatchedImported.isEmpty)
    }
}

@Suite("Completion from imported data")
struct CompletionRatioTests {

    private func workout(_ discipline: Discipline) -> PlannedWorkout {
        let parameters = TrainingParameters()
        switch discipline {
        case .running:
            return WorkoutTemplates.runWalk(on: .now, parameters: parameters)
        case .swimming:
            return WorkoutTemplates.techniqueSwim(on: .now, parameters: parameters)
        default:
            return WorkoutTemplates.easyRide(on: .now, parameters: parameters)
        }
    }

    private func activity(_ sport: Sport, duration: TimeInterval, distance: Double? = nil) -> ImportedWorkout {
        ImportedWorkout(
            healthKitUUID: UUID(),
            sport: sport,
            startDate: .now,
            endDate: Date.now.addingTimeInterval(duration),
            duration: duration,
            distanceMeters: distance
        )
    }

    @Test("Running completion is judged on duration")
    func runningUsesDuration() {
        let run = workout(.running)

        #expect(run.completionRatio(for: activity(.running, duration: 1680)) == 1.0)
        #expect(run.completionRatio(for: activity(.running, duration: 840)) == 0.5)
    }

    @Test("Swimming completion is judged on distance")
    func swimmingUsesDistance() {
        let swim = workout(.swimming)

        #expect(swim.completionRatio(for: activity(.swimming, duration: 600, distance: 300)) == 1.0)
        #expect(swim.completionRatio(for: activity(.swimming, duration: 600, distance: 150)) == 0.5)
    }

    @Test("Doing more than prescribed is still full completion")
    func overCompletionIsClamped() {
        let ride = workout(.cycling)

        #expect(ride.completionRatio(for: activity(.cycling, duration: 5400)) == 1.0)
    }

    @Test("A swim with no recorded distance is not judged a failure")
    func missingMetricsDoNotPenalise() {
        let swim = workout(.swimming)

        #expect(swim.completionRatio(for: activity(.swimming, duration: 600)) == 1.0)
    }
}

@Suite("Health data provider contract")
struct HealthDataProvidingTests {

    @Test("Workouts outside the window are excluded")
    func windowIsRespected() async throws {
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        let provider = StubHealthDataProvider(
            stored: [
                ImportedWorkout(
                    healthKitUUID: UUID(), sport: .running,
                    startDate: now, endDate: now.addingTimeInterval(1800), duration: 1800
                ),
                ImportedWorkout(
                    healthKitUUID: UUID(), sport: .cycling,
                    startDate: now.addingTimeInterval(-10 * 86_400),
                    endDate: now.addingTimeInterval(-10 * 86_400 + 1800), duration: 1800
                )
            ]
        )

        let recent = try await provider.workouts(from: now.addingTimeInterval(-86_400), to: now)

        #expect(recent.count == 1)
        #expect(recent.first?.sport == .running)
    }

    @Test("Reading without authorization fails rather than returning nothing")
    func unauthorizedReadThrows() async {
        let provider = StubHealthDataProvider(status: .denied)

        await #expect(throws: HealthDataError.notAuthorized) {
            try await provider.workouts(from: .distantPast, to: .distantFuture)
        }
    }
}
