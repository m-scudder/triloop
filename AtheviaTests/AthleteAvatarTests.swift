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
        avatar.equip(item)

        #expect(avatar.runLoadout.top == .runTopGraphite)
        #expect(avatar.cycleLoadout == cyclingBefore)
    }

    @Test("Locked preview gear cannot be equipped early")
    func lockedGearDoesNotEquip() throws {
        var avatar = AthleteAvatar.starter
        let locked = try #require(AvatarGearCatalog.item(.runTopCobalt))
        let before = avatar.runLoadout

        avatar.equip(locked)

        #expect(avatar.runLoadout == before)
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
