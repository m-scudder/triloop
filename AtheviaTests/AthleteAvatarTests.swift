import Foundation
import Testing

@testable import Athevia

@Suite("Athlete avatar")
struct AthleteAvatarTests {
    @Test("Starter avatar has deterministic sport loadouts")
    func starterLoadouts() {
        let avatar = AthleteAvatar.starter

        #expect(avatar.runLoadout == .starterRun)
        #expect(avatar.cycleLoadout == .starterCycle)
        #expect(avatar.swimLoadout == .starterSwim)
    }

    @Test("Starter gear can be equipped without affecting other sports")
    func equipStarterGear() throws {
        var avatar = AthleteAvatar.starter
        let item = try #require(AvatarGearCatalog.item(.runTopGraphite))

        let cyclingBefore = avatar.cycleLoadout
        avatar.equip(item, isUnlocked: true)

        #expect(avatar.runLoadout.top == .runTopGraphite)
        #expect(avatar.cycleLoadout == cyclingBefore)
    }

    @Test("Locked preview gear cannot be equipped early")
    func lockedGearDoesNotEquip() throws {
        var avatar = AthleteAvatar.starter
        let locked = try #require(AvatarGearCatalog.item(.runTopCobalt))
        let before = avatar.runLoadout

        avatar.equip(locked, isUnlocked: false)

        #expect(avatar.runLoadout == before)
    }

    @Test("Workout-count rewards unlock from completed training evidence")
    func workoutCountUnlocks() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let workouts = (0..<3).map { index in
            PlannedWorkout(
                date: date.addingTimeInterval(Double(index) * 86_400),
                discipline: .running,
                title: "Run \(index + 1)",
                status: .completed
            )
        }
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: date,
            endDate: date.addingTimeInterval(6 * 86_400),
            workouts: workouts
        )

        let rewards = AvatarRewardEvaluator().evaluate(
            setup: AthleteSetup(),
            plans: [plan],
            asOf: date.addingTimeInterval(7 * 86_400)
        )

        #expect(rewards.runningCompleted == 3)
        #expect(rewards.unlockedGearIDs.contains(.runTopIvory))
        #expect(!rewards.unlockedGearIDs.contains(.runShortSlate))
    }

    @Test("Milestone rewards use the existing journey evidence")
    func milestoneUnlocks() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = PlannedWorkout(
            date: date,
            discipline: .running,
            title: "5K",
            status: .completed
        )
        workout.importedSummary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: date,
            endDate: date.addingTimeInterval(1_800),
            duration: 1_800,
            distanceMeters: 5_000,
            source: "avatar-test"
        )
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: date,
            endDate: date.addingTimeInterval(6 * 86_400),
            workouts: [workout]
        )

        let rewards = AvatarRewardEvaluator().evaluate(
            setup: AthleteSetup(),
            plans: [plan],
            asOf: date.addingTimeInterval(86_400)
        )

        #expect(rewards.milestones.contains { $0.kind == .firstFiveK })
        #expect(rewards.unlockedGearIDs.contains(.runShoeCobalt))
    }

    @Test("Avatar survives AthleteSetup coding round trip")
    func setupCodingRoundTrip() throws {
        var avatar = AthleteAvatar.starter
        avatar.presentation = .masculine
        avatar.skinTone = .deep
        avatar.hairStyle = .cropped
        avatar.bodyPreset = .powerful

        let setup = AthleteSetup(avatar: avatar)
        let data = try JSONEncoder().encode(setup)
        let restored = try JSONDecoder().decode(AthleteSetup.self, from: data)

        #expect(restored.avatar == avatar)
    }

    @Test("Legacy setup without avatar gets safe starter identity")
    func legacySetupFallback() throws {
        let data = Data(#"{"goal":"generalFitness"}"#.utf8)
        let setup = try JSONDecoder().decode(AthleteSetup.self, from: data)

        #expect(setup.avatar == .starter)
    }
}
