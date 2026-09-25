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
        #expect(snapshot.capabilities.first?.currentEvidence == "Run/walk reported")
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
