import Foundation
import SwiftData
import Testing

@testable import Athevia

@MainActor
struct SeedWeekOneTests {

    private func makeContext() throws -> ModelContext {
        let container = try AtheviaModelContainer.make(inMemory: true)
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

    @Test func seedIsAFixedThreeSportWeek() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)

        // A development fixture, not an athlete's plan: no availability, no
        // real-world dates, the same every time.
        #expect(plan.orderedWorkouts.map(\.discipline) == [
            .running, .swimming, .cycling, .running, .swimming, .cycling, .rest
        ])
    }

    @Test func sixTrainingSessionsInWeekOne() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        #expect(plan.trainingSessions.count == 6)
    }

    @Test func seedIsIndependentOfTheDateItStartsOn() throws {
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)) ?? monday()

        let august = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let later = SeedWeekOne.makePlan(startDate: september, calendar: calendar)

        #expect(august.orderedWorkouts.map(\.discipline) == later.orderedWorkouts.map(\.discipline))
    }

    @Test func runWalkIsDistanceBased() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })

        #expect(run.targetDistanceMeters == 2_000)
        #expect(run.estimatedDistanceMeters == 2_000)
        #expect(run.steps.allSatisfy { $0.totalDistanceMeters != nil })
        #expect(run.targetRPE == RPERange(3, 4))
    }

    @Test func swimTotalsThreeHundredMetres() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let swim = try #require(plan.orderedWorkouts.first { $0.discipline == .swimming })

        #expect(swim.estimatedDistanceMeters == 300)
        let derived = swim.steps.compactMap(\.totalDistanceMeters).reduce(0, +)
        #expect(derived == 300)
    }

    @Test func rideIsDistanceBased() throws {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        let ride = try #require(plan.orderedWorkouts.first { $0.discipline == .cycling })

        #expect(ride.targetDistanceMeters == 4_000)
        #expect(ride.estimatedDistanceMeters == 4_000)
        #expect(ride.steps.allSatisfy { $0.totalDistanceMeters != nil })
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

    @Test func theSeedStartsOnTheDayItIsInstalled() throws {
        let today = calendar.date(from: DateComponents(year: 2027, month: 3, day: 4)) ?? .now

        #expect(SeedWeekOne.defaultStartDate(calendar: calendar, now: today) == today)
    }

    @Test func installedSeedCoversToday() throws {
        let context = try makeContext()
        let today = Calendar.current.startOfDay(for: .now)

        SeedDataInstaller.installIfNeeded(in: context)
        let plan = try #require(try context.fetch(FetchDescriptor<WeeklyPlan>()).first)

        #expect(plan.contains(today))
        #expect(plan.startDate == today)
    }

    @Test func startOverRecordsAHealthBoundaryAndPendingFreshStart() throws {
        TrainingResetBoundary.clearForTesting()
        defer { TrainingResetBoundary.clearForTesting() }

        let context = try makeContext()
        context.insert(SeedWeekOne.makeProfile(startDate: monday()))
        context.insert(SeedWeekOne.makePlan(startDate: monday(), calendar: calendar))
        try context.save()

        let resetAt = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 22, hour: 23, minute: 45)
        ) ?? .now

        SeedDataInstaller.eraseAll(in: context, at: resetAt)

        #expect(TrainingResetBoundary.latest == resetAt)
        #expect(TrainingResetBoundary.isFreshStartPending)
        #expect(try context.fetchCount(FetchDescriptor<AthleteProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 0)

        TrainingResetBoundary.completeFreshStart()

        #expect(TrainingResetBoundary.isFreshStartPending == false)
        #expect(TrainingResetBoundary.latest == resetAt)
    }

    /// A reset used to reinstall a week fixed to August 2026, which left the
    /// athlete looking at a week that had already ended.
    @Test func resetStartsFromToday() throws {
        let context = try makeContext()
        context.insert(SeedWeekOne.makePlan(startDate: monday(), calendar: calendar))
        try context.save()

        SeedDataInstaller.reset(in: context)

        let plans = try context.fetch(FetchDescriptor<WeeklyPlan>())
        let plan = try #require(plans.first)

        #expect(plans.count == 1)
        #expect(plan.startDate == Calendar.current.startOfDay(for: .now))
        #expect(plan.contains(.now))
    }
}
