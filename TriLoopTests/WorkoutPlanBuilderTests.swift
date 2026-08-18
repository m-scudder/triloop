import Foundation
import HealthKit
import Testing
import WorkoutKit

@testable import TriLoop

@Suite("WorkoutKit conversion")
struct WorkoutPlanBuilderTests {

    private func session(_ discipline: Discipline) -> PlannedWorkout {
        let parameters = TrainingParameters()
        switch discipline {
        case .running:
            return WorkoutTemplates.runWalk(on: .now, parameters: parameters)
        case .swimming:
            return WorkoutTemplates.techniqueSwim(on: .now, parameters: parameters)
        case .cycling:
            return WorkoutTemplates.easyRide(on: .now, parameters: parameters)
        case .recovery:
            return WorkoutTemplates.recoveryDay(on: .now)
        case .rest:
            return WorkoutTemplates.restDay(on: .now)
        }
    }

    @Test("Run intervals become one repeating block")
    func runBecomesAnIntervalBlock() throws {
        let workout = try #require(WorkoutPlanBuilder.customWorkout(for: session(.running)))

        #expect(workout.activity == .running)
        #expect(workout.displayName == "Running")
        #expect(workout.warmup?.goal == .time(300, .seconds))
        #expect(workout.cooldown?.goal == .time(300, .seconds))

        #expect(workout.blocks.count == 1)
        let block = try #require(workout.blocks.first)
        #expect(block.iterations == 6)
        #expect(block.steps.map(\.purpose) == [.work, .recovery])
        #expect(block.steps.first?.step.goal == .time(60, .seconds))
        #expect(block.steps.last?.step.goal == .time(120, .seconds))
    }

    @Test("Step titles travel to the Watch")
    func stepNamesArePreserved() throws {
        let workout = try #require(WorkoutPlanBuilder.customWorkout(for: session(.running)))
        let block = try #require(workout.blocks.first)

        #expect(workout.warmup?.displayName == "Brisk walk")
        #expect(block.steps.first?.step.displayName == "Easy run")
        #expect(block.steps.last?.step.displayName == "Walk")
    }

    @Test("Swim steps are prescribed by distance")
    func swimUsesDistanceGoals() throws {
        let workout = try #require(WorkoutPlanBuilder.customWorkout(for: session(.swimming)))

        #expect(workout.activity == .swimming)
        #expect(workout.location == .indoor)
        // Warm-up is a quarter of the 300 m session, rounded to whole lengths.
        #expect(workout.warmup?.goal == .distance(75, .meters))
        #expect(workout.blocks.count == 2)
        #expect(workout.blocks.allSatisfy { $0.iterations == 1 })
        #expect(workout.blocks.first?.steps.first?.step.goal == .distance(125, .meters))
    }

    @Test("A ride is warm-up, work and cooldown")
    func rideIsASingleBlock() throws {
        let workout = try #require(WorkoutPlanBuilder.customWorkout(for: session(.cycling)))

        #expect(workout.activity == .cycling)
        #expect(workout.location == .outdoor)
        #expect(workout.blocks.count == 1)
        #expect(workout.blocks.first?.steps.first?.step.goal == .time(1200, .seconds))
    }

    @Test("Rest and recovery days are not sent to the Watch")
    func nonSportDaysProduceNothing() {
        #expect(WorkoutPlanBuilder.customWorkout(for: session(.rest)) == nil)
        #expect(WorkoutPlanBuilder.customWorkout(for: session(.recovery)) == nil)
        #expect(WorkoutPlanBuilder.plan(for: session(.rest)) == nil)
    }

    @Test("The plan keeps the workout's identity")
    func planReusesTheWorkoutIdentifier() throws {
        let workout = session(.running)
        let plan = try #require(WorkoutPlanBuilder.plan(for: workout))

        #expect(plan.id == workout.id)
        if case .custom = plan.workout {} else {
            Issue.record("Expected a custom workout")
        }
    }
}

@Suite("Schedule timing")
struct ScheduleTimingTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? .now
    }

    @Test("A future session is scheduled for the morning")
    func futureSessionUsesTheMorning() {
        let workout = WorkoutTemplates.runWalk(
            on: date(day: 18, hour: 0), parameters: TrainingParameters()
        )

        let when = workout.suggestedScheduleDate(
            now: date(day: 17, hour: 10), preferredHour: 7, calendar: calendar
        )

        #expect(when == date(day: 18, hour: 7))
    }

    @Test("A session whose hour has passed is scheduled shortly from now")
    func pastHourMovesForward() {
        let now = date(day: 17, hour: 10)
        let workout = WorkoutTemplates.runWalk(
            on: date(day: 17, hour: 0), parameters: TrainingParameters()
        )

        let when = workout.suggestedScheduleDate(now: now, preferredHour: 7, calendar: calendar)

        #expect(when > now)
        #expect(when == now.addingTimeInterval(600))
    }
}

@Suite("Scheduling contract")
struct WorkoutSchedulingTests {

    @Test("An authorized scheduler records the session")
    func schedulingSucceeds() async throws {
        let scheduler = StubWorkoutScheduler()
        let workout = WorkoutTemplates.runWalk(
            on: .now, parameters: TrainingParameters()
        )

        try await scheduler.schedule(workout, at: .now)

        #expect(scheduler.scheduled.count == 1)
        #expect(scheduler.scheduled.first?.workoutID == workout.id)
    }

    @Test("A rest day cannot be scheduled")
    func restDayIsRejected() async {
        let scheduler = StubWorkoutScheduler()
        let rest = WorkoutTemplates.restDay(on: .now)

        await #expect(throws: WorkoutSchedulingError.unsupportedWorkout) {
            try await scheduler.schedule(rest, at: .now)
        }
    }

    @Test("Scheduling without a Watch fails clearly")
    func missingWatchIsReported() async {
        let scheduler = StubWorkoutScheduler(isSupported: false)
        let workout = WorkoutTemplates.easyRide(on: .now, parameters: TrainingParameters())

        await #expect(throws: WorkoutSchedulingError.unavailable) {
            try await scheduler.schedule(workout, at: .now)
        }
    }
}
