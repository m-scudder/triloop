import Foundation
import Testing

@testable import Athevia

@Suite("Journey progress")
struct JourneyProgressTests {
    @Test("Capability never fabricates event readiness without evidence")
    func noEvidence() {
        let setup = AthleteSetup(
            objective: .event(
                sport: .running,
                distance: EventDistance(kind: .run5K)
            ),
            baseline: AthleteBaseline(running: .runWalk),
            schedule: .everyDay(),
            preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)]
        )

        let snapshot = JourneyProgressBuilder().build(setup: setup, plans: [])

        #expect(snapshot.capabilities.count == 1)
        #expect(snapshot.capabilities.first?.state == .notEnoughData)
        #expect(snapshot.capabilities.first?.currentEvidence == "2.0 km starting baseline")
    }

    @Test("Recorded event distance is demonstrated capability")
    func demonstratedDistance() {
        let setup = AthleteSetup(
            objective: .event(
                sport: .running,
                distance: EventDistance(kind: .run5K)
            ),
            baseline: AthleteBaseline(running: .regular5K),
            schedule: .everyDay(),
            preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)]
        )
        let plan = SeedWeekOne.makePlan()
        let run = plan.trainingSessions.first { $0.discipline == .running }!
        run.importedSummary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: run.date,
            endDate: run.date.addingTimeInterval(1_800),
            duration: 1_800,
            distanceMeters: 5_000,
            source: "Test"
        )
        run.status = .completed

        let snapshot = JourneyProgressBuilder().build(setup: setup, plans: [plan])
        #expect(snapshot.capabilities.first?.state == .demonstrated)
        #expect(snapshot.capabilities.first?.currentEvidence == "5.0 km recorded recently · starting baseline 5.0 km")
    }

    @Test("Recorded distance can be compared with the onboarding baseline without becoming the target")
    func baselineDistanceComparison() {
        let setup = AthleteSetup(
            baseline: AthleteBaseline(
                running: .regular5K,
                swimming: .continuous50,
                cycling: .fortyFiveToSixty
            ),
            schedule: .everyDay(),
            preferences: Sport.allCases.map { SportPreference(sport: $0, sessionsPerWeek: 1) }
        )
        let plan = SeedWeekOne.makePlan()
        let run = plan.trainingSessions.first { $0.discipline == .running }!
        run.importedSummary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: run.date,
            endDate: run.date.addingTimeInterval(1_800),
            duration: 1_800,
            distanceMeters: 4_500,
            source: "Test"
        )
        run.status = .completed

        let capability = AthleteCapabilityAssessmentBuilder().build(
            setup: setup,
            plans: [plan],
            asOf: run.date
        )
        let comparison = capability.distanceComparison(for: .running)

        #expect(comparison?.baselineMeters == 5_000)
        #expect(comparison?.recordedMeters == 4_500)
        #expect(comparison?.deltaMeters == -500)
        #expect(comparison?.recordedToBaselineRatio == 0.9)
        #expect(capability.running.longestRecordedDistanceMeters == 4_500)
    }

    @Test("Milestones are derived from immutable completed history")
    func milestones() {
        let setup = AthleteSetup(
            objective: .event(
                sport: .triathlon,
                distance: EventDistance(kind: .triathlonSprint)
            ),
            schedule: .everyDay(),
            preferences: Sport.allCases.map { SportPreference(sport: $0, sessionsPerWeek: 1) }
        )
        let plan = SeedWeekOne.makePlan()
        let workout = plan.trainingSessions.first!
        workout.title = "Bike + Run Brick"
        workout.status = .completed
        workout.completedAt = workout.date

        let snapshot = JourneyProgressBuilder().build(setup: setup, plans: [plan])
        #expect(snapshot.milestones.contains(where: { $0.kind == .firstRun }))
        #expect(snapshot.milestones.contains(where: { $0.kind == .firstBrick }))
    }

    @Test("Changing objective does not mutate completed history")
    func objectiveChangeKeepsHistory() {
        var setup = AthleteSetup(
            objective: .event(sport: .running, distance: EventDistance(kind: .run5K)),
            schedule: .everyDay(),
            preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)]
        )
        let plan = SeedWeekOne.makePlan()
        let workout = plan.trainingSessions.first!
        workout.status = .completed
        workout.completedAt = workout.date
        let completion = workout.completedAt

        _ = JourneyProgressBuilder().build(setup: setup, plans: [plan])
        setup.objective = .event(sport: .running, distance: EventDistance(kind: .run10K))
        _ = JourneyProgressBuilder().build(setup: setup, plans: [plan])

        #expect(workout.isCompleted)
        #expect(workout.completedAt == completion)
    }
}
