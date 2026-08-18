import Foundation
import SwiftData

/// The fixed development week, for previews, tests and Developer tools.
///
/// Never installed automatically: a real athlete's first week comes from
/// onboarding, and a seeded week would collide with it.
@MainActor
enum SeedDataInstaller {

    /// Installs the seed on an empty store. Previews and tests only.
    @discardableResult
    static func installIfNeeded(in context: ModelContext) -> Bool {
        guard isStoreEmpty(context) else { return false }
        let startDate = SeedWeekOne.defaultStartDate()
        context.insert(SeedWeekOne.makeProfile(startDate: startDate))
        context.insert(SeedWeekOne.makePlan(startDate: startDate))
        try? context.save()
        return true
    }

    /// Replaces training history with the fixed seed week, leaving the athlete
    /// and their setup answers alone.
    static func reset(in context: ModelContext) {
        eraseTraining(in: context)
        context.insert(SeedWeekOne.makePlan(startDate: SeedWeekOne.defaultStartDate()))
        try? context.save()
    }

    /// Clears everything, profile included, so the next launch starts at
    /// onboarding rather than resuming a half-configured athlete.
    static func eraseAll(in context: ModelContext) {
        for model in TriLoopSchema.models {
            try? context.delete(model: model)
        }
        try? context.save()
    }

    /// Everything except the athlete themselves.
    private static func eraseTraining(in context: ModelContext) {
        try? context.delete(model: WeeklyPlan.self)
        try? context.delete(model: PlannedWorkout.self)
        try? context.delete(model: WorkoutStep.self)
        try? context.delete(model: WorkoutFeedback.self)
        try? context.delete(model: ImportedWorkoutSummary.self)
        try? context.delete(model: RecoveryCheckIn.self)
    }

    private static func isStoreEmpty(_ context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<WeeklyPlan>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count == 0
    }
}
