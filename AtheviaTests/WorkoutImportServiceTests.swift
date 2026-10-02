import Foundation
import SwiftData
import Testing

@testable import Athevia

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
        ModelContext(try AtheviaModelContainer.make(inMemory: true))
    }

    private func service(_ context: ModelContext, _ stored: [ImportedWorkout]) -> WorkoutImportService {
        WorkoutImportService(
            context: context,
            provider: StubHealthDataProvider(stored: stored),
            matcher: WorkoutMatcher(calendar: calendar, toleranceDays: 1),
            calendar: calendar,
            importCutoff: nil
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


    @Test("Historical import creates standalone completed Run Swim and Cycle workouts")
    func historicalImportIsStandaloneAndIdempotent() async throws {
        let context = try makeContext()
        let workouts = [
            activity(.running, on: -30, duration: 1_800, distance: 5_000),
            activity(.swimming, on: -20, duration: 1_200, distance: 600),
            activity(.cycling, on: -10, duration: 2_400, distance: 15_000)
        ]
        let importer = service(context, workouts)

        let first = try await importer.importHistoricalWorkouts(
            from: day(-40, hour: 0),
            to: day(0, hour: 23)
        )
        let second = try await importer.importHistoricalWorkouts(
            from: day(-40, hour: 0),
            to: day(0, hour: 23)
        )

        let stored = try context.fetch(FetchDescriptor<PlannedWorkout>())
            .filter { $0.origin == .imported }
            .sorted { $0.date < $1.date }

        #expect(first.unrecognised == 3)
        #expect(second.unrecognised == 0)
        #expect(second.alreadyKnown == 3)
        #expect(stored.count == 3)
        #expect(stored.allSatisfy { $0.plan == nil })
        #expect(stored.allSatisfy(\.isCompleted))
        #expect(stored.map(\.title) == ["Run", "Swim", "Cycle"])
    }

    @Test("Workouts from before Start Over are not re-imported")
    func resetBoundaryBlocksOldHealthWorkouts() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)

        let oldWorkout = activity(.running, on: 0)
        let newWorkout = activity(.swimming, on: 1, distance: 300)
        let boundary = day(1, hour: 0)

        var importer = service(context, [oldWorkout, newWorkout])
        importer.importCutoff = boundary

        let outcome = try await importer.importWorkouts(for: plan)

        #expect(outcome.matched == 1)
        #expect(outcome.unrecognised == 0)
        #expect(outcome.alreadyKnown == 0)

        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        let swim = try #require(plan.orderedWorkouts.first { $0.discipline == .swimming })

        #expect(run.isCompleted == false)
        #expect(run.importedSummary == nil)
        #expect(swim.isCompleted)
        #expect(swim.importedSummary?.healthKitUUID == newWorkout.healthKitUUID)
        #expect(try context.fetch(FetchDescriptor<ImportedWorkoutSummary>()).count == 1)
        #expect(plan.trainingSessions.filter { $0.origin == .imported }.isEmpty)
    }

    @Test("A fresh first plan ignores workouts from before it was generated")
    func initialPlanDoesNotClaimEarlierHealthHistory() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        plan.generationReasonCode = .initialAssessment
        plan.generatedAt = day(1, hour: 0)

        let oldWorkout = activity(.running, on: 0)
        let newWorkout = activity(.swimming, on: 1, distance: 300)

        let outcome = try await service(context, [oldWorkout, newWorkout])
            .importWorkouts(for: plan)

        #expect(outcome.matched == 1)

        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        let swim = try #require(plan.orderedWorkouts.first { $0.discipline == .swimming })

        #expect(run.isCompleted == false)
        #expect(run.importedSummary == nil)
        #expect(swim.isCompleted)
        #expect(swim.importedSummary?.healthKitUUID == newWorkout.healthKitUUID)
    }

    @Test("Activities that match nothing are reported, not attached")
    func unrecognisedActivitiesAreReported() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)

        // Sunday is a rest day, so a run then belongs to no planned session.
        let outcome = try await service(context, [activity(.running, on: 6)]).importWorkouts(for: plan)

        #expect(outcome.matched == 0)
        #expect(outcome.unrecognised == 1)
        #expect(try context.fetch(FetchDescriptor<ImportedWorkoutSummary>()).count == 1)
        let recorded = try #require(plan.trainingSessions.first { $0.origin == .imported })
        #expect(recorded.isCompleted)
        #expect(recorded.awaitingFeedback)
        let repeatImport = try await service(context, [recorded.importedSummary!.imported]).importWorkouts(for: plan)
        #expect(repeatImport.alreadyKnown == 1)
        #expect(plan.trainingSessions.filter { $0.origin == .imported }.count == 1)
    }


    @Test("A Watch swim started early stays on its actual date")
    func earlyWatchSwimBecomesRecordedWorkoutToday() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        let plannedSwim = try #require(plan.orderedWorkouts.first { $0.discipline == .swimming })
        let actualStart = day(0, hour: 18)

        let imported = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .swimming,
            startDate: actualStart,
            endDate: actualStart.addingTimeInterval(1_200),
            duration: 1_200,
            distanceMeters: 500,
            plannedWorkoutID: plannedSwim.id,
            source: "com.mayankagarwal.athevia.watch"
        )

        let outcome = try await service(context, [imported]).importWorkouts(for: plan)

        #expect(outcome.matched == 0)
        #expect(outcome.unrecognised == 1)
        #expect(!plannedSwim.isCompleted)
        #expect(plannedSwim.importedSummary == nil)

        let recorded = try #require(
            plan.trainingSessions.first {
                $0.origin == .imported
                    && $0.discipline == .swimming
                    && calendar.isDate($0.date, inSameDayAs: actualStart)
            }
        )
        #expect(recorded.isCompleted)
        #expect(recorded.importedSummary?.healthKitUUID == imported.healthKitUUID)
    }


    @Test("Previously misdated Watch imports are repaired on sync")
    func existingMisdatedWatchImportIsReconciled() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        let plannedSwim = try #require(plan.orderedWorkouts.first { $0.discipline == .swimming })
        let actualStart = day(0, hour: 18)

        let imported = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .swimming,
            startDate: actualStart,
            endDate: actualStart.addingTimeInterval(1_200),
            duration: 1_200,
            distanceMeters: 500,
            plannedWorkoutID: plannedSwim.id,
            source: "com.mayankagarwal.athevia.watch"
        )
        let summary = ImportedWorkoutSummary(imported)
        context.insert(summary)
        plannedSwim.attach(summary)
        try context.save()

        _ = try await service(context, []).importWorkouts(for: plan)

        #expect(!plannedSwim.isCompleted)
        #expect(plannedSwim.importedSummary == nil)

        let recorded = try #require(
            plan.trainingSessions.first {
                $0.origin == .imported
                    && $0.discipline == .swimming
                    && calendar.isDate($0.date, inSameDayAs: actualStart)
            }
        )
        #expect(recorded.isCompleted)
        #expect(recorded.importedSummary?.healthKitUUID == imported.healthKitUUID)
    }

    @Test("A short unmatched activity does not complete a longer prescription")
    func shortSessionReducesTheLoad() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)

        // Half of the prescribed 28 minutes.
        try await service(context, [activity(.running, on: 0, duration: 840)]).importWorkouts(for: plan)

        let run = try #require(plan.trainingSessions.first {
            $0.discipline == .running && $0.origin == .generated
        })
        #expect(!run.isCompleted)
        #expect(run.importedSummary == nil)
        #expect(plan.trainingSessions.filter { $0.origin == .imported }.count == 1)
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



    @Test("Running sensor metrics survive Health import")
    func runningMetricsPersist() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        let start = run.date.addingTimeInterval(3_600)

        let imported = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: start,
            endDate: start.addingTimeInterval(1_680),
            duration: 1_680,
            distanceMeters: 4_500,
            averageHeartRate: 148,
            maximumHeartRate: 171,
            elevationAscendedMeters: 62,
            metrics: RecordedMetrics(
                averageCadence: 172,
                averageRunningSpeed: 2.68,
                averageRunningPower: 248,
                averageStrideLength: 1.06,
                averageGroundContactTime: 238,
                averageVerticalOscillation: 8.1,
                activeEnergyKilocalories: 285
            )
        )

        let outcome = try await service(context, [imported]).importWorkouts(for: plan)

        #expect(outcome.matched == 1)
        let summary = try #require(run.importedSummary)
        #expect(summary.averageHeartRate == 148)
        #expect(summary.maximumHeartRate == 171)
        #expect(summary.elevationAscendedMeters == 62)
        #expect(summary.metrics?.averageCadence == 172)
        #expect(summary.metrics?.averageRunningSpeed == 2.68)
        #expect(summary.metrics?.averageRunningPower == 248)
        #expect(summary.metrics?.averageStrideLength == 1.06)
        #expect(summary.metrics?.averageGroundContactTime == 238)
        #expect(summary.metrics?.averageVerticalOscillation == 8.1)
        #expect(summary.metrics?.activeEnergyKilocalories == 285)
    }

    @Test("Cycling sensor metrics survive Health import")
    func cyclingMetricsPersist() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        let ride = try #require(plan.orderedWorkouts.first { $0.discipline == .cycling })
        let start = ride.date.addingTimeInterval(3_600)

        let imported = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .cycling,
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            duration: 1_800,
            distanceMeters: 12_000,
            averageHeartRate: 142,
            maximumHeartRate: 166,
            elevationAscendedMeters: 105,
            metrics: RecordedMetrics(
                averageCyclingSpeed: 6.67,
                averageCyclingCadence: 87,
                averageCyclingPower: 196,
                activeEnergyKilocalories: 330
            )
        )

        let outcome = try await service(context, [imported]).importWorkouts(for: plan)

        #expect(outcome.matched == 1)
        let summary = try #require(ride.importedSummary)
        #expect(summary.averageHeartRate == 142)
        #expect(summary.maximumHeartRate == 166)
        #expect(summary.elevationAscendedMeters == 105)
        #expect(summary.metrics?.averageCyclingSpeed == 6.67)
        #expect(summary.metrics?.averageCyclingCadence == 87)
        #expect(summary.metrics?.averageCyclingPower == 196)
        #expect(summary.metrics?.activeEnergyKilocalories == 330)
    }

    @Test("Unplanned multisport import preserves individual legs")
    func multisportSegmentsPersist() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        let start = day(6, hour: 7)
        let segments = [
            RecordedMultisportSegment(
                sport: .swimming,
                durationSeconds: 600,
                distanceMeters: 400,
                swimEnvironment: .openWater
            ),
            RecordedMultisportSegment(
                sport: nil,
                isTransition: true,
                durationSeconds: 90
            ),
            RecordedMultisportSegment(
                sport: .cycling,
                durationSeconds: 1_800,
                distanceMeters: 12_000
            ),
            RecordedMultisportSegment(
                sport: .running,
                durationSeconds: 900,
                distanceMeters: 2_500
            )
        ]

        let imported = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .swimming,
            startDate: start,
            endDate: start.addingTimeInterval(3_390),
            duration: 3_390,
            averageHeartRate: 151,
            maximumHeartRate: 178,
            swimmingLengths: 16,
            swimmingStrokeCount: 288,
            longestContinuousSwimMeters: 200,
            metrics: RecordedMetrics(
                activeEnergyKilocalories: 510,
                multisportSegments: segments
            )
        )

        let outcome = try await service(context, [imported]).importWorkouts(for: plan)

        #expect(outcome.matched == 0)
        #expect(outcome.unrecognised == 1)
        let recorded = try #require(
            plan.trainingSessions.first {
                $0.origin == .imported && $0.discipline == .multisport
            }
        )
        let summary = try #require(recorded.importedSummary)
        #expect(summary.discipline == .multisport)
        #expect(summary.metrics?.multisportSegments == segments)
        #expect(summary.swimmingLengths == 16)
        #expect(summary.swimmingStrokeCount == 288)
        #expect(summary.longestContinuousSwimMeters == 200)
        #expect(summary.metrics?.activeEnergyKilocalories == 510)
    }

    @Test("Known HealthKit workouts refresh richer metrics without duplicating")
    func knownWorkoutMetricsAreRefreshed() async throws {
        let context = try makeContext()
        let plan = seededPlan(in: context)
        let swim = try #require(plan.orderedWorkouts.first { $0.discipline == .swimming })
        let id = UUID()
        let start = swim.date.addingTimeInterval(3_600)

        let initial = ImportedWorkout(
            healthKitUUID: id,
            sport: .swimming,
            startDate: start,
            endDate: start.addingTimeInterval(900),
            duration: 900,
            distanceMeters: 300,
            metrics: RecordedMetrics()
        )

        _ = try await service(context, [initial]).importWorkouts(for: plan)
        let summary = try #require(swim.importedSummary)
        #expect(summary.swimmingStrokeCount == nil)
        #expect(summary.metrics?.activeEnergyKilocalories == nil)

        let richer = ImportedWorkout(
            healthKitUUID: id,
            sport: .swimming,
            startDate: start,
            endDate: start.addingTimeInterval(900),
            duration: 900,
            distanceMeters: 300,
            swimmingLengths: 12,
            swimmingStrokeCount: 210,
            longestContinuousSwimMeters: 150,
            metrics: RecordedMetrics(
                activeEnergyKilocalories: 145,
                swimEnvironment: .pool
            )
        )

        let outcome = try await service(context, [richer]).importWorkouts(for: plan)

        #expect(outcome.alreadyKnown == 1)
        #expect(outcome.matched == 0)
        #expect(try context.fetch(FetchDescriptor<ImportedWorkoutSummary>()).count == 1)
        #expect(summary.swimmingLengths == 12)
        #expect(summary.swimmingStrokeCount == 210)
        #expect(summary.longestContinuousSwimMeters == 150)
        #expect(summary.metrics?.activeEnergyKilocalories == 145)
        #expect(summary.metrics?.swimEnvironment == .pool)
    }

    @Test("Automatic import covers the current week and the one before it")
    func autoImportCoversRecentWeeks() async throws {
        // Anchored to the current calendar: the importer builds its own matcher,
        // so a fixed UTC week would not line up with the device's time zone.
        let current = Calendar.current
        let thisWeek = try #require(current.dateInterval(of: .weekOfYear, for: .now)?.start)
        let lastWeek = try #require(current.date(byAdding: .day, value: -7, to: thisWeek))

        let container = try AtheviaModelContainer.make(inMemory: true)
        let context = container.mainContext

        let previous = SeedWeekOne.makePlan(startDate: lastWeek, calendar: current)
        previous.generatedAt = lastWeek
        context.insert(previous)

        let latest = SeedWeekOne.makePlan(startDate: thisWeek, calendar: current)
        latest.weekNumber = 2
        latest.generatedAt = thisWeek
        context.insert(latest)
        try context.save()

        let runs = [previous, latest].compactMap { plan in
            plan.orderedWorkouts.first { $0.discipline == .running }
        }
        let stored = runs.map { run in
            let startDate = run.date.addingTimeInterval(3_600)
            return ImportedWorkout(
                healthKitUUID: UUID(),
                sport: .running,
                startDate: startDate,
                endDate: startDate.addingTimeInterval(1680),
                duration: 1680,
                averageHeartRate: 132
            )
        }

        let importer = WorkoutAutoImporter(
            container: container,
            provider: StubHealthDataProvider(stored: stored),
            importCutoff: nil
        )

        let importedCount = await importer.importRecentWeeks()
        #expect(importedCount == 2)
    }

    @Test("Automatic import does nothing without authorization")
    func autoImportRequiresAuthorization() async throws {
        let container = try AtheviaModelContainer.make(inMemory: true)
        container.mainContext.insert(
            SeedWeekOne.makePlan(startDate: Calendar.current.startOfDay(for: .now))
        )

        let importer = WorkoutAutoImporter(
            container: container,
            provider: StubHealthDataProvider(status: .denied, stored: [activity(.running, on: 0)])
        )

        #expect(await importer.importRecentWeeks() == 0)
    }
}


@Suite("Workout auto-import reset boundary", .serialized)
@MainActor
struct WorkoutAutoImportResetBoundaryTests {

    @Test("Reset seed data advances the Health import boundary")
    func resetSeedAdvancesImportBoundary() throws {
        TrainingResetBoundary.clearForTesting()
        defer { TrainingResetBoundary.clearForTesting() }

        let container = try AtheviaModelContainer.make(inMemory: true)
        let resetAt = Date(timeIntervalSince1970: 1_800_000_000)

        SeedDataInstaller.reset(in: container.mainContext, on: resetAt)

        #expect(TrainingResetBoundary.latest == resetAt)
    }

    @Test("Auto importer observes a reset boundary created after launch")
    func autoImporterObservesRuntimeResetBoundary() async throws {
        TrainingResetBoundary.clearForTesting()
        defer { TrainingResetBoundary.clearForTesting() }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let container = try AtheviaModelContainer.make(inMemory: true)
        let context = container.mainContext
        let plan = SeedWeekOne.makePlan(startDate: today, calendar: calendar)
        context.insert(plan)
        try context.save()

        let run = try #require(plan.orderedWorkouts.first { $0.discipline == .running })
        let startDate = run.date.addingTimeInterval(60)
        let oldWorkout = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1_680),
            duration: 1_680,
            averageHeartRate: 132
        )

        let importer = WorkoutAutoImporter(
            container: container,
            provider: StubHealthDataProvider(stored: [oldWorkout])
        )

        // The importer already exists before the reset boundary advances.
        TrainingResetBoundary.latest = oldWorkout.endDate.addingTimeInterval(60)

        #expect(await importer.importRecentWeeks() == 0)
        #expect(run.isCompleted == false)
    }
}
