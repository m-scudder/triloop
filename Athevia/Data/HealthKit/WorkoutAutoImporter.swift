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

    /// Keeps Apple Health training history visible even when automatic plan
    /// matching is disabled. Historical visibility is a data-source concern,
    /// not a training-plan preference.
    @discardableResult
    func syncHistoricalTrainingHistory() async -> Int {
        guard !PhoneWorkoutExecutionState.isActive else { return 0 }
        guard await health.authorizationStatus == .authorized else { return 0 }

        let context = container.mainContext
        let descriptor = FetchDescriptor<WeeklyPlan>(
            sortBy: [SortDescriptor(\.startDate)]
        )
        let plans = (try? context.fetch(descriptor)) ?? []
        let boundary = WorkoutImportService.historicalBoundary(
            for: plans
        )

        let service = WorkoutImportService(
            context: context,
            provider: health,
            importCutoff: effectiveImportCutoff
        )

        guard let outcome = try? await service.syncHistoricalTrainingHistory(
            before: boundary
        ) else {
            return 0
        }

        return outcome.unrecognised
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

        imported += await syncHistoricalTrainingHistory()

        for plan in plans.suffix(2) {
            guard let outcome = try? await service.importWorkouts(for: plan) else {
                continue
            }
            imported += outcome.matched + outcome.unrecognised
        }

        return imported
    }
}
