import Foundation
import SwiftData
import Testing

@testable import TriLoop

@Suite("Cloud backup foundation")
@MainActor
struct BackupSnapshotTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try TriLoopModelContainer.make(inMemory: true))
    }

    @Test("Snapshot round-trips profile, plan, report, recovery and GPS route")
    func snapshotRoundTrip() throws {
        let context = try makeContext()
        let profile = AthleteProfile(
            name: "Athlete",
            trainingStartDate: Date(timeIntervalSince1970: 1_780_000_000)
        )
        context.insert(profile)

        let routePoint = RecordedRoutePoint(
            latitude: 17.385,
            longitude: 78.4867,
            altitudeMeters: 510,
            timestamp: Date(timeIntervalSince1970: 1_780_100_100)
        )
        let workout = PlannedWorkout(
            date: Date(timeIntervalSince1970: 1_780_099_200),
            discipline: .running,
            title: "Easy Run",
            goal: "Build consistency",
            targetRPE: RPERange(3, 4),
            prescribedDurationSeconds: 1_800,
            origin: .generated,
            steps: [
                WorkoutStep.repeating(
                    order: 0,
                    title: "Run / walk",
                    count: 2,
                    children: [
                        WorkoutStep(
                            order: 0,
                            kind: .work,
                            title: "Run",
                            durationSeconds: 60,
                            targetIntensity: .easy
                        ),
                        WorkoutStep(
                            order: 1,
                            kind: .recovery,
                            title: "Walk",
                            durationSeconds: 120,
                            targetIntensity: .veryEasy
                        )
                    ]
                )
            ]
        )
        workout.recordCompletion(
            with: FeedbackDraft(rpe: 4, recoveryFeeling: .good, notes: "Smooth"),
            at: Date(timeIntervalSince1970: 1_780_101_000)
        )
        workout.attach(
            ImportedWorkoutSummary(
                healthKitUUID: UUID(),
                sport: .running,
                startDate: Date(timeIntervalSince1970: 1_780_100_000),
                endDate: Date(timeIntervalSince1970: 1_780_101_000),
                duration: 1_000,
                distanceMeters: 2_500,
                metrics: RecordedMetrics(averageRunningSpeed: 2.5, route: [routePoint]),
                source: "TriLoop iPhone"
            )
        )
        workout.recordRecoveryCheckIn(
            painScore: 0,
            soreness: .mild,
            energy: .good,
            at: Date(timeIntervalSince1970: 1_780_180_000)
        )

        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: Date(timeIntervalSince1970: 1_779_840_000),
            endDate: Date(timeIntervalSince1970: 1_780_358_400),
            workouts: [workout]
        )
        context.insert(plan)

        let template = StoredWorkoutTemplate(
            sport: .running,
            name: "My Run",
            category: .easy,
            structure: WorkoutStructure()
        )
        context.insert(template)
        try context.save()

        let captured = try BackupSnapshot.capture(
            from: context,
            at: Date(timeIntervalSince1970: 1_780_200_000)
        )
        let encoded = try JSONEncoder().encode(captured)
        let decoded = try JSONDecoder().decode(BackupSnapshot.self, from: encoded)

        #expect(decoded.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(decoded.profile?.id == profile.id)
        #expect(decoded.plans.count == 1)
        #expect(decoded.templates.count == 1)
        #expect(decoded.plans[0].workouts[0].feedback?.rpe == 4)
        #expect(decoded.plans[0].workouts[0].recoveryCheckIn?.soreness == .mild)
        #expect(decoded.plans[0].workouts[0].steps[0].children.count == 2)
        #expect(decoded.plans[0].workouts[0].importedSummary?.metrics?.route == [routePoint])
    }

    @Test("Restore rebuilds the relationships into an empty store")
    func restoreRebuildsRelationships() throws {
        let source = try makeContext()
        let profile = AthleteProfile(name: "Athlete", trainingStartDate: .now)
        source.insert(profile)

        let workout = PlannedWorkout(
            date: .now,
            discipline: .cycling,
            title: "Easy Ride",
            origin: .custom,
            steps: [
                WorkoutStep(
                    order: 0,
                    kind: .work,
                    title: "Ride",
                    durationSeconds: 600,
                    targetIntensity: .easy
                )
            ]
        )
        workout.recordCompletion(with: FeedbackDraft(rpe: 3))
        let plan = WeeklyPlan(
            weekNumber: 3,
            startDate: .now,
            endDate: .now.addingTimeInterval(6 * 86_400),
            workouts: [workout]
        )
        source.insert(plan)
        try source.save()

        let snapshot = try BackupSnapshot.capture(from: source)

        let destination = try makeContext()
        try BackupRestoreService().restore(snapshot, into: destination)

        let profiles = try destination.fetch(FetchDescriptor<AthleteProfile>())
        let plans = try destination.fetch(FetchDescriptor<WeeklyPlan>())
        let workouts = try destination.fetch(FetchDescriptor<PlannedWorkout>())

        #expect(profiles.count == 1)
        #expect(plans.count == 1)
        #expect(workouts.count == 1)
        #expect(workouts[0].plan?.id == plans[0].id)
        #expect(workouts[0].feedback?.workout?.id == workouts[0].id)
        #expect(workouts[0].steps.first?.workout?.id == workouts[0].id)
        #expect(workouts[0].origin == .custom)
    }

    @Test("Restore refuses to overwrite local training")
    func restoreRejectsNonEmptyStore() throws {
        let source = try makeContext()
        source.insert(AthleteProfile(name: "Cloud", trainingStartDate: .now))
        try source.save()
        let snapshot = try BackupSnapshot.capture(from: source)

        let destination = try makeContext()
        destination.insert(AthleteProfile(name: "Local", trainingStartDate: .now))
        try destination.save()

        #expect(throws: BackupRestoreError.localStoreNotEmpty) {
            try BackupRestoreService().restore(snapshot, into: destination)
        }
    }
}
