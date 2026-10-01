import Foundation
import Testing

@testable import Athevia

@Suite("Coach conversation persistence")
struct CoachConversationPersistenceTests {
    @Test("Conversation history is athlete scoped and reloadable")
    func athleteScopedHistory() {
        let defaults = UserDefaults(suiteName: "CoachConversationPersistenceTests")!
        defaults.removePersistentDomain(forName: "CoachConversationPersistenceTests")

        let first = CoachConversationStore(athleteScopeID: "athlete-a", defaults: defaults)
        let second = CoachConversationStore(athleteScopeID: "athlete-b", defaults: defaults)

        var conversation = first.create(at: Date(timeIntervalSince1970: 10))
        conversation.title = "Analyze my run"
        conversation.messages = [
            CoachChatMessage(
                role: .athlete,
                text: "Analyze my run",
                createdAt: Date(timeIntervalSince1970: 11)
            ),
            CoachChatMessage(
                role: .coach,
                text: "Your recorded run was steady.",
                evidence: ["5.0 km recorded"],
                createdAt: Date(timeIntervalSince1970: 12)
            )
        ]
        conversation.updatedAt = Date(timeIntervalSince1970: 12)
        first.saveConversation(conversation)

        #expect(first.conversations().first?.title == "Analyze my run")
        #expect(first.conversations().first?.messages.count == 2)
        #expect(second.conversations().isEmpty)
    }
}

@Suite("Coach temporary time off")
struct CoachTimeOffStoreTests {
    @Test("Time off only removes dates inside the temporary range")
    func temporaryScheduleOverride() throws {
        let defaults = UserDefaults(suiteName: "CoachTimeOffStoreTests")!
        defaults.removePersistentDomain(forName: "CoachTimeOffStoreTests")

        let calendar = CoachTestFixture.calendar
        let store = CoachTimeOffStore(athleteScopeID: "athlete-a", defaults: defaults)
        let start = CoachTestFixture.date(year: 2026, month: 10, day: 5)
        let end = CoachTestFixture.date(year: 2026, month: 10, day: 7)
        #expect(store.record(start: start, end: end, calendar: calendar) != nil)

        let base = AthleteSchedule.everyDay(maxDurationMinutes: 60)
        let result = store.schedule(from: base, weekStarting: start, calendar: calendar)

        #expect(result.availability(on: .monday).isAvailable == false)
        #expect(result.availability(on: .tuesday).isAvailable == false)
        #expect(result.availability(on: .wednesday).isAvailable == false)
        #expect(result.availability(on: .thursday).isAvailable == true)
        #expect(result.availability(on: .sunday).isAvailable == true)
    }
}

@Suite("Coach deterministic scheduling language")
@MainActor
struct CoachSchedulingIntentTests {
    @Test("Move and skip requests stay on the deterministic path")
    func moveAndSkip() async {
        let plan = CoachTestFixture.seedPlan(
            startDate: CoachTestFixture.date(year: 2026, month: 9, day: 28)
        )
        let profile = CoachTestFixture.profile()
        let context = CoachTestFixture.context(profile: profile, plans: [plan])
        let interpreter = DeterministicCoachIntentInterpreter(
            calendar: CoachTestFixture.calendar
        )

        let move = await interpreter.interpret(
            request: "Move Tuesday's workout to Thursday",
            context: context,
            plan: plan,
            now: CoachTestFixture.date(year: 2026, month: 9, day: 28)
        )
        let skip = await interpreter.interpret(
            request: "Skip Wednesday's workout",
            context: context,
            plan: plan,
            now: CoachTestFixture.date(year: 2026, month: 9, day: 28)
        )

        if case .intent(.moveSession(let source, let target)) = move {
            #expect(Weekday(date: source, calendar: CoachTestFixture.calendar) == .tuesday)
            #expect(Weekday(date: target, calendar: CoachTestFixture.calendar) == .thursday)
        } else {
            Issue.record("Move request did not stay deterministic.")
        }

        if case .intent(.skipSession(let date)) = skip {
            #expect(Weekday(date: date, calendar: CoachTestFixture.calendar) == .wednesday)
        } else {
            Issue.record("Skip request did not stay deterministic.")
        }
    }
}
