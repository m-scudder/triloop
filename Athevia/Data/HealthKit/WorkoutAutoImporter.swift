import Foundation
import SwiftData

/// Keeps the plan in step with HealthKit without the athlete tapping Import.
///
/// Two triggers, because they cover different failures: the observer catches a
/// workout saved while Athevia is closed, and the foreground pass catches
/// anything the observer missed — a denied wake, a delayed Watch sync, or
/// background delivery being unavailable at all.
@MainActor
final class WorkoutAutoImporter {
    private let container: ModelContainer
    private let health: any HealthDataProviding
    private let fixedImportCutoff: Date?
    private let followsTrainingResetBoundary: Bool
    private let observer = WorkoutObserver()

    init(
        container: ModelContainer,
        provider: any HealthDataProviding = HealthKitWorkoutImporter()
    ) {
        self.container = container
        self.health = provider
        self.fixedImportCutoff = nil
        self.followsTrainingResetBoundary = true
    }

    init(
        container: ModelContainer,
        provider: any HealthDataProviding,
        importCutoff: Date?
    ) {
        self.container = container
        self.health = provider
        self.fixedImportCutoff = importCutoff
        self.followsTrainingResetBoundary = false
    }

    private var effectiveImportCutoff: Date? {
        followsTrainingResetBoundary ? TrainingResetBoundary.latest : fixedImportCutoff
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
        // Do not mutate planned-workout completion while its phone player owns
        // execution. A delayed HealthKit/Watch import can otherwise replace the
        // Today subtree and dismiss the full-screen timer mid-workout.
        guard !PhoneWorkoutExecutionState.isActive else { return 0 }
        guard await health.authorizationStatus == .authorized else { return 0 }

        let context = container.mainContext
        let descriptor = FetchDescriptor<WeeklyPlan>(sortBy: [SortDescriptor(\.startDate)])
        guard let plans = try? context.fetch(descriptor) else { return 0 }

        let service = WorkoutImportService(
            context: context,
            provider: health,
            importCutoff: effectiveImportCutoff
        )
        var imported = 0

        // Apple Health history is independent of the current Athevia plan.
        // A reset/re-onboarding may create a new first plan today, but yesterday's
        // real Run/Swim/Cycle must remain visible across the app.
        let historyBoundary = plans.first?.startDate ?? Date.now
        if let outcome = try? await service.syncHistoricalTrainingHistory(
            before: historyBoundary
        ) {
            imported += outcome.unrecognised
        }

        for plan in plans.suffix(2) {
            guard let outcome = try? await service.importWorkouts(for: plan) else {
                continue
            }
            imported += outcome.matched + outcome.unrecognised
        }

        return imported
    }
}
