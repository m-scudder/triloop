import Foundation
import SwiftData
import Testing

@testable import Athevia

@Suite("Account profile confirmation")
@MainActor
struct AccountProfileSetupTests {
    private func context() throws -> ModelContext {
        ModelContext(
            try AtheviaModelContainer.make(
                inMemory: true
            )
        )
    }

    @Test("New account stores confirmed name and birth date")
    func createsProfile() throws {
        let context = try context()
        let birthDate = Date(
            timeIntervalSince1970: 631_152_000
        )

        try AccountProfileDetailsStore.save(
            name: "  Mayank Agarwal  ",
            birthDate: birthDate,
            in: context
        )

        let profile = try #require(
            context.fetch(
                FetchDescriptor<AthleteProfile>()
            ).first
        )

        #expect(profile.name == "Mayank Agarwal")
        #expect(profile.setup?.birthDate == birthDate)
        #expect(
            !AccountProfileDetailsStore
                .requiresConfirmation(in: context)
        )
    }

    @Test("Confirming details preserves existing onboarding answers")
    func preservesExistingSetup() throws {
        let context = try context()
        var setup = AthleteSetup()
        setup.trainingDayTarget = 4
        setup.stage = .days

        let profile = AthleteProfile(
            name: "",
            trainingStartDate: .now,
            poolLengthMeters: 50,
            setup: setup
        )
        context.insert(profile)
        try context.save()

        let birthDate = Date(
            timeIntervalSince1970: 631_152_000
        )
        try AccountProfileDetailsStore.save(
            name: "Mayank",
            birthDate: birthDate,
            in: context
        )

        #expect(profile.name == "Mayank")
        #expect(profile.setup?.birthDate == birthDate)
        #expect(profile.setup?.trainingDayTarget == 4)
        #expect(profile.setup?.stage == .days)
        #expect(profile.poolLengthMeters == 50)
    }

    @Test("Apple name is used only as a suggestion")
    func suggestedNameUsesAppleFallback() throws {
        let context = try context()
        let session = AccountSession(
            userID: "user",
            email: "relay@privaterelay.appleid.com",
            suggestedName: "Apple Supplied Name"
        )

        #expect(
            AccountProfileDetailsStore.initialName(
                session: session,
                in: context
            ) == "Apple Supplied Name"
        )

        let profile = AthleteProfile(
            name: "Confirmed Name",
            trainingStartDate: .now
        )
        context.insert(profile)
        try context.save()

        #expect(
            AccountProfileDetailsStore.initialName(
                session: session,
                in: context
            ) == "Confirmed Name"
        )
    }
}
