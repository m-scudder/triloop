import Foundation
import SwiftData

@MainActor
enum SeedDataInstaller {

    /// Installs the development seed exactly once, on an empty store.
    @discardableResult
    static func installIfNeeded(in context: ModelContext) -> Bool {
        guard isStoreEmpty(context) else { return false }
        install(in: context)
        return true
    }

    /// Wipes TriLoop-owned data and reinstalls the seed. Used by Developer Mode.
    static func reset(in context: ModelContext) {
        for model in TriLoopSchema.models {
            try? context.delete(model: model)
        }
        install(in: context)
    }

    private static func install(in context: ModelContext) {
        let startDate = SeedWeekOne.defaultStartDate()
        context.insert(SeedWeekOne.makeProfile(startDate: startDate))
        context.insert(SeedWeekOne.makePlan(startDate: startDate))
        try? context.save()
    }

    private static func isStoreEmpty(_ context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<WeeklyPlan>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count == 0
    }
}
