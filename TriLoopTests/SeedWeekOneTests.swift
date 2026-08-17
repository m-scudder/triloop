import Foundation
import SwiftData
import Testing

@testable import TriLoop

@MainActor
struct SeedWeekOneTests {

    private func makeContext() throws -> ModelContext {
        let container = try TriLoopModelContainer.make(inMemory: true)
        return ModelContext(container)
    }

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

    @Test func planCoversSevenConsecutiveDays() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)

        #expect(plan.weekNumber == 1)
        #expect(plan.orderedWorkouts.count == 7)

        let days = calendar.dateComponents([.day], from: plan.startDate, to: plan.endDate).day
        #expect(days == 6)
    }

    @Test func disciplinesMatchTheAthletesFirstWeek() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)

        // Swimming starts in September and the bike arrives on the Thursday, so
        // week one is running until it does, then two rides.
        #expect(plan.orderedWorkouts.map(\.discipline) == [
            .running, .running, .running, .running, .cycling, .cycling, .rest
        ])
    }

    @Test func sixTrainingSessionsInWeekOne() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        #expect(plan.trainingSessions.count == 6)
    }

    @Test func swimmingIsHeldBackUntilItsStartDate() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        #expect(plan.orderedWorkouts.contains { $0.discipline == .swimming } == false)

        // Mid-September, once swimming is available, all three sports appear.
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)) ?? monday()
        let later = SeedWeekOne.makePlan(startDate: september, calendar: calendar)

        #expect(later.orderedWorkouts.map(\.discipline) == [
            .running, .swimming, .cycling, .running, .swimming, .cycling, .rest
        ])
    }

    @Test func cyclingWaitsForTheBike() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let rides = plan.orderedWorkouts.filter { $0.discipline == .cycling }

        // Friday 21 August is the first day a ride can be prescribed.
        let friday = calendar.date(byAdding: .day, value: 4, to: monday()) ?? monday()
        #expect(rides.allSatisfy { $0.date >= friday })
    }

    @Test func runWalkExpandsToTwentyEightMinutes() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })

        // 5 min warm-up + 6 × (1:00 run + 2:00 walk) + 5 min cooldown.
        // Expected value is explicitly typed: #expect captures each operand
        // separately, so a bare literal would default to Int and never compare
        // equal to the TimeInterval on the left.
        #expect(run.estimatedDurationSeconds == TimeInterval(28 * 60))
        #expect(run.targetRPE == RPERange(3, 4))
    }

    @Test func swimTotalsThreeHundredMetres() throws {
        let plan = SeedWeekOne.makePlan(
            startDate: monday(), calendar: calendar, availability: .everything
        )
        let swim = try #require(plan.orderedWorkouts.first { $0.discipline == .swimming })

        #expect(swim.estimatedDistanceMeters == 300)
        let derived = swim.steps.compactMap(\.totalDistanceMeters).reduce(0, +)
        #expect(derived == 300)
    }

    @Test func rideTotalsThirtyMinutes() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let ride = try #require(plan.orderedWorkouts.first { $0.discipline == .cycling })

        #expect(ride.estimatedDurationSeconds == TimeInterval(30 * 60))
    }

    @Test func restDayHasNoPrescribedWork() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let rest = try #require(plan.orderedWorkouts.first { $0.discipline == .rest })

        #expect(rest.steps.isEmpty)
        #expect(rest.discipline.sport == nil)
    }

    @Test func seedInstallsOnceOnly() throws {
        let context = try makeContext()

        #expect(SeedDataInstaller.installIfNeeded(in: context) == true)
        #expect(SeedDataInstaller.installIfNeeded(in: context) == false)

        let plans = try context.fetch(FetchDescriptor<WeeklyPlan>())
        #expect(plans.count == 1)
        #expect(plans.first?.workouts.count == 7)
    }

    @Test func seededPlanPersistsItsStepTree() throws {
        let context = try makeContext()
        SeedDataInstaller.installIfNeeded(in: context)

        let plan = try #require(try context.fetch(FetchDescriptor<WeeklyPlan>()).first)
        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        let block = try #require(run.orderedSteps.first { $0.kind == .repeatBlock })

        #expect(block.repeatCount == 6)
        #expect(block.orderedChildren.count == 2)
        #expect(block.orderedChildren.map(\.kind) == [.work, .recovery])
    }
}
