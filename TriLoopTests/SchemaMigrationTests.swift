import Foundation
import SwiftData
import Testing

@testable import TriLoop

@Suite("Schema and migration")
@MainActor
struct SchemaMigrationTests {

    @Test("Each schema version has a migration stage into it")
    func planCoversTheCurrentVersion() {
        #expect(TriLoopSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(TriLoopSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        // A version cannot reuse another's model shape, and every version after
        // the first needs a stage, or existing stores cannot be opened.
        #expect(TriLoopMigrationPlan.stages.count == TriLoopMigrationPlan.schemas.count - 1)
    }

    @Test("Versions are ordered oldest first, which is the order they migrate in")
    func schemasAreOrdered() {
        let versions = TriLoopMigrationPlan.schemas.map(\.versionIdentifier)

        #expect(versions == versions.sorted())
    }

    @Test("Every persisted model is part of the versioned schema")
    func versionedSchemaCoversEveryModel() {
        let names = Set(TriLoopSchemaV4.models.map { String(describing: $0) })

        #expect(names == [
            "AthleteProfile",
            "WeeklyPlan",
            "PlannedWorkout",
            "WorkoutStep",
            "WorkoutFeedback",
            "ImportedWorkoutSummary",
            "RecoveryCheckIn"
        ])
    }

    @Test("The frozen version still describes the same set of models")
    func frozenVersionCoversEveryModel() {
        let frozen = Set(TriLoopSchemaV3.models.map { String(describing: $0) })
        let current = Set(TriLoopSchemaV4.models.map { String(describing: $0) })

        // A lightweight stage cannot add or drop an entity, only properties.
        #expect(frozen == current)
    }

    @Test("A container opens against the versioned schema")
    func containerOpensWithMigrationPlan() throws {
        let container = try TriLoopModelContainer.make(inMemory: true)

        #expect(container.migrationPlan != nil)
        #expect(container.schema.version == TriLoopSchemaV4.versionIdentifier)
    }

    @Test("Metrics stored by an older build load once new fields are added")
    func recordedMetricsDecodeWithMissingKeys() throws {
        // What a build that predates every field would have written.
        let stored = Data("{}".utf8)

        let metrics = try JSONDecoder().decode(RecordedMetrics.self, from: stored)

        #expect(metrics.averageCadence == nil)
        #expect(metrics.isEmpty)
    }

    @Test("Recorded metrics survive a container reopen")
    func metricsRoundTrip() throws {
        let container = try TriLoopModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let summary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: .now,
            endDate: .now.addingTimeInterval(1800),
            duration: 1800,
            metrics: RecordedMetrics(averageCadence: 164)
        )
        context.insert(summary)
        try context.save()

        let reopened = ModelContext(container)
        let stored = try reopened.fetch(FetchDescriptor<ImportedWorkoutSummary>())

        #expect(stored.first?.metrics?.averageCadence == 164)
    }

    @Test("A summary stored without metrics reads back rather than trapping")
    func missingMetricsAreRepresentable() throws {
        let container = try TriLoopModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        // What every row written before the property existed looks like.
        let summary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .cycling,
            startDate: .now,
            endDate: .now.addingTimeInterval(1200),
            duration: 1200
        )
        context.insert(summary)
        try context.save()

        let stored = try ModelContext(container).fetch(FetchDescriptor<ImportedWorkoutSummary>())

        #expect(stored.first?.metrics == nil)
        #expect(stored.first?.metrics?.averageCadence == nil)
    }

    @Test("Feedback survives a container reopen")
    func dataSurvivesReopening() throws {
        let container = try TriLoopModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let plan = SeedWeekOne.makePlan()
        context.insert(plan)
        let run = try #require(plan.trainingSessions.first { $0.discipline == .running })
        run.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 1, painLocations: [.calf]))
        run.recordRecoveryCheckIn(painScore: 2, soreness: .mild, energy: .normal)
        try context.save()

        let reopened = ModelContext(container)
        let stored = try reopened.fetch(FetchDescriptor<WorkoutFeedback>())
        let checkIns = try reopened.fetch(FetchDescriptor<RecoveryCheckIn>())

        #expect(stored.count == 1)
        #expect(stored.first?.rpe == 4)
        #expect(stored.first?.painLocations == [.calf])
        #expect(checkIns.first?.soreness == .mild)
    }
}
