import Foundation
import SwiftData
import Testing

@testable import TriLoop

@Suite("Workout import")
@MainActor
struct WorkoutImportServiceTests {

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
        on offset: Int,
        duration: TimeInterval = 1680,
        distance: Double? = nil
    ) -> ImportedWorkout {
        let start = day(offset)
        return ImportedWorkout(
            healthKitUUID: UUID(),
            sport: sport,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            duration: duration,
            distanceMeters: distance,
            averageHeartRate: 132,
            source: "com.apple.workout"
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try TriLoopModelContainer.make(inMemory: true))
    }

    private func service(_ context: ModelContext, _ stored: [ImportedWorkout]) -> WorkoutImportService {
        WorkoutImportService(
            context: context,
            provider: StubHealthDataProvider(stored: stored),
            matcher: WorkoutMatcher(calendar: calendar, toleranceDays: 1),
            calendar: calendar
        )
    }

    private func seededPlan(in context: ModelContext) -> WeeklyPlan {
        let plan = SeedWeekOne.makePlan(startDate: monday(), calendar: calendar)
        context.insert(plan)
        return plan
    }

    @Test("A matched activity completes the session and stores its metrics")
    func importAttachesSummary() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        let outcome = try await service(context, [activity(.running, on: 0)]).importWorkouts(for: plan)

        #expect(outcome.matched == 1)

        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        #expect(run.isCompleted)
        #expect(run.awaitingFeedback)
        #expect(run.importedSummary?.averageHeartRate == 132)
        #expect(run.importedSummary?.source == "com.apple.workout")
        #expect(try context.fetch(FetchDescriptor<ImportedWorkoutSummary>()).count == 1)
    }

    @Test("Importing twice imports nothing twice")
    func importIsIdempotent() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        let activities = [activity(.running, on: 0), activity(.swimming, on: 1, distance: 300)]
        let service = service(context, activities)

        let first = try await service.importWorkouts(for: plan)
        let second = try await service.importWorkouts(for: plan)

        #expect(first.matched == 2)
        #expect(second.matched == 0)
        #expect(second.alreadyKnown == 2)
        #expect(try context.fetch(FetchDescriptor<ImportedWorkoutSummary>()).count == 2)
    }

    @Test("Activities that match nothing are reported, not attached")
    func unrecognisedActivitiesAreReported() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)

        // Sunday is a rest day, so a run then belongs to no planned session.
        let outcome = try await service(context, [activity(.running, on: 6)]).importWorkouts(for: plan)

        #expect(outcome.matched == 0)
        #expect(outcome.unrecognised == 1)
        #expect(try context.fetch(FetchDescriptor<ImportedWorkoutSummary>()).isEmpty)
    }

    @Test("Imported data supplies real completion to the analysis")
    func shortSessionReducesTheLoad() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)

        // Half of the prescribed 28 minutes.
        try await service(context, [activity(.running, on: 0, duration: 840)]).importWorkouts(for: plan)

        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        #expect(run.recordedCompletion == 0.5)

        run.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        let running = WeeklyAnalyser().analyse(plan).analysis(for: .running)

        // Comfortable effort, but only half the session was completed.
        #expect(running?.status == .reduce)
    }

    @Test("A session completed as prescribed still progresses")
    func fullSessionStillProgresses() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)

        for offset in [0, 3] {
            try await service(context, [activity(.running, on: offset)]).importWorkouts(for: plan)
        }

        for run in plan.trainingSessions where run.discipline == .running {
            run.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0))
        }

        let running = WeeklyAnalyser().analyse(plan).analysis(for: .running)
        #expect(running?.status == .progress)
    }

    @Test("Analysis reports the distance actually swum")
    func analysisUsesImportedDistance() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)

        try await service(context, [activity(.swimming, on: 1, duration: 900, distance: 250)])
            .importWorkouts(for: plan)

        for swim in plan.trainingSessions where swim.discipline == .swimming {
            swim.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 0))
        }

        let swimming = WeeklyAnalyser().analyse(plan).analysis(for: .swimming)

        // 250 m imported for Tuesday, 300 m planned for the unmatched Friday swim.
        #expect(swimming?.totalDistanceMeters == 550)
    }
}
