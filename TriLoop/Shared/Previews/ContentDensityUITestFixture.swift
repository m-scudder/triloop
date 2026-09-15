#if DEBUG
import Foundation
import SwiftData

@MainActor
enum ContentDensityUITestFixture {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--content-density-ui-tests") || isOnboarding
    }

    private static var isOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("--onboarding-ui-tests")
    }

    static func makeContainer() -> ModelContainer {
        do {
            let container = try TriLoopModelContainer.make(inMemory: true)
            if isOnboarding { return container }
            let today = Calendar.current.startOfDay(for: .now)
            let start = Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today
            let previous = SeedWeekOne.makePlan(startDate: start)
            let current = SeedWeekOne.makePlan(startDate: today)
            current.weekNumber = 2
            previous.status = .completed
            for workout in previous.trainingSessions {
                workout.recordCompletion(with: FeedbackDraft(
                    rpe: workout.discipline == .running ? 8 : 3,
                    painScore: workout.discipline == .running ? 3 : 0
                ))
            }
            let profile = SeedWeekOne.makeProfile(startDate: start)
            var setup = AthleteSetup()
            setup.stage = .complete
            setup.completedAt = .now
            profile.setup = setup
            container.mainContext.insert(profile)
            container.mainContext.insert(previous)
            container.mainContext.insert(current)
            try container.mainContext.save()
            return container
        } catch {
            fatalError("Could not create the in-memory UI test fixture: \(error)")
        }
    }
}
#endif