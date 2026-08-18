import Foundation
import SwiftData

/// Keeps the plan in step with HealthKit without the athlete tapping Import.
///
/// Two triggers, because they cover different failures: the observer catches a
/// workout saved while TriLoop is closed, and the foreground pass catches
/// anything the observer missed — a denied wake, a delayed Watch sync, or
/// background delivery being unavailable at all.
@MainActor
final class WorkoutAutoImporter {
    private let container: ModelContainer
    private let health: any HealthDataProviding
    private let observer = WorkoutObserver()

    init(container: ModelContainer, provider: any HealthDataProviding = HealthKitWorkoutImporter()) {
        self.container = container
        self.health = provider
    }

    /// Read directly rather than through `@AppStorage`, because registration has
    /// to happen at launch, before any view exists.
    static var isEnabledByPreference: Bool {
        UserDefaults.standard.object(forKey: "automaticallyImportWorkouts") as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            await observer.stop()
            return
        }
        guard await health.authorizationStatus == .authorized else { return }

        try? await observer.start { [weak self] in
            await self?.importRecentWeeks()
        }
    }

    /// The current week and the one before it. A session finished late on a
    /// Sunday can be saved after the next week has already begun.
    @discardableResult
    func importRecentWeeks() async -> Int {
        guard await health.authorizationStatus == .authorized else { return 0 }

        let context = container.mainContext
        let descriptor = FetchDescriptor<WeeklyPlan>(sortBy: [SortDescriptor(\.startDate)])
        guard let plans = try? context.fetch(descriptor) else { return 0 }

        let service = WorkoutImportService(context: context, provider: health)
        var matched = 0

        for plan in plans.suffix(2) {
            guard let outcome = try? await service.importWorkouts(for: plan) else { continue }
            matched += outcome.matched
        }
        return matched
    }
}
