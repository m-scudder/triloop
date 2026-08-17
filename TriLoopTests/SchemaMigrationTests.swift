import Foundation
import SwiftData
import Testing

@testable import TriLoop

@Suite("Schema and migration")
@MainActor
struct SchemaMigrationTests {

    @Test("Each schema version has a migration stage into it")
    func planCoversTheCurrentVersion() {
        #expect(TriLoopSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        // A version cannot reuse another's model shape, and every version after
        // the first needs a stage, or existing stores cannot be opened.
        #expect(TriLoopMigrationPlan.stages.count == TriLoopMigrationPlan.schemas.count - 1)
    }

    @Test("Every persisted model is part of the versioned schema")
    func versionedSchemaCoversEveryModel() {
        let names = Set(TriLoopSchemaV2.models.map { String(describing: $0) })

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

    @Test("A container opens against the versioned schema")
    func containerOpensWithMigrationPlan() throws {
        let container = try TriLoopModelContainer.make(inMemory: true)

        #expect(container.migrationPlan != nil)
        #expect(container.schema.version == TriLoopSchemaV2.versionIdentifier)
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
