import Foundation
import SwiftData

/// The fixed development week, for previews, tests and Developer tools.
///
/// Never installed automatically: a real athlete's first week comes from
/// onboarding, and a seeded week would collide with it.
/// Persists the moment the athlete deliberately started over.
///
/// SwiftData is erased during a reset, but Apple Health is not. Keeping this
/// boundary outside SwiftData prevents pre-reset Health workouts from being
/// imported back into the fresh plan after relaunch.
enum TrainingResetBoundary {
    private static let key = "trainingResetAt"
    private static let pendingFreshStartKey = "trainingResetPendingFreshStart"

    static var latest: Date? {
        get {
            guard let seconds = UserDefaults.standard.object(forKey: key) as? Double else {
                return nil
            }
            return Date(timeIntervalSince1970: seconds)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    static var isFreshStartPending: Bool {
        UserDefaults.standard.bool(forKey: pendingFreshStartKey)
    }

    static func mark(_ date: Date = .now) {
        latest = date
        UserDefaults.standard.set(true, forKey: pendingFreshStartKey)
    }

    static func completeFreshStart() {
        UserDefaults.standard.set(false, forKey: pendingFreshStartKey)
    }

    #if DEBUG
    static func clearForTesting() {
        latest = nil
        UserDefaults.standard.removeObject(forKey: pendingFreshStartKey)
    }
    #endif
}

@MainActor
enum SeedDataInstaller {

    /// Installs the seed on an empty store. Previews and tests only.
    @discardableResult
    static func installIfNeeded(in context: ModelContext, on date: Date = .now) -> Bool {
        guard isStoreEmpty(context) else { return false }
        let startDate = SeedWeekOne.defaultStartDate(now: date)
        context.insert(SeedWeekOne.makeProfile(startDate: startDate))
        context.insert(SeedWeekOne.makePlan(startDate: startDate))
        try? context.save()
        return true
    }

    /// Replaces training history with the fixed seed week, leaving the athlete
    /// and their setup answers alone. The week starts today, so a reset always
    /// lands the athlete in a week they are actually in.
    static func reset(in context: ModelContext, on date: Date = .now) {
        eraseTraining(in: context)
        context.insert(SeedWeekOne.makePlan(startDate: SeedWeekOne.defaultStartDate(now: date)))
        try? context.save()
    }

    /// Clears everything, profile included, so the next launch starts at
    /// onboarding rather than resuming a half-configured athlete.
    static func eraseAll(in context: ModelContext, at date: Date = .now) {
        // HealthKit survives an app reset. Record the boundary before deleting
        // local data so automatic import cannot resurrect earlier activities.
        TrainingResetBoundary.mark(date)

        for model in AtheviaSchema.models {
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
