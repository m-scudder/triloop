#if DEBUG
import Foundation
import SwiftData

@MainActor
enum ContentDensityUITestFixture {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--content-density-ui-tests")
            || isOnboarding
            || isEventProfile
            || isOpenWaterProfile
    }

    private static var isOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("--onboarding-ui-tests")
    }

    private static var isEventProfile: Bool {
        ProcessInfo.processInfo.arguments.contains("--event-profile-ui-tests")
    }

    private static var isOpenWaterProfile: Bool {
        ProcessInfo.processInfo.arguments.contains("--open-water-profile-ui-tests")
    }

    static func makeContainer() -> ModelContainer {
        do {
            let container = try AtheviaModelContainer.make(inMemory: true)
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
            if isOpenWaterProfile {
                setup.objective = .event(
                    sport: .triathlon,
                    distance: EventDistance(kind: .triathlonSprint),
                    eventDate: Calendar.current.date(byAdding: .day, value: 56, to: today),
                    targetIntent: .complete
                )
                setup.baseline = AthleteBaseline(
                    running: .regular5K,
                    swimming: .continuous200Plus,
                    cycling: .sixtyPlus
                )
                setup.preferences = Sport.allCases.map {
                    SportPreference(sport: $0, sessionsPerWeek: 2)
                }
                setup.schedule = .everyDay()
            } else if isEventProfile {
                setup.objective = .event(
                    sport: .running,
                    distance: EventDistance(kind: .run5K),
                    eventDate: Calendar.current.date(byAdding: .day, value: 70, to: today),
                    targetIntent: .complete
                )
                setup.preferences = [
                    SportPreference(sport: .running, sessionsPerWeek: 3)
                ]
                setup.schedule = .everyDay()
            }
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