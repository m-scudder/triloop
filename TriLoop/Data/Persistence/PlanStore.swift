import Foundation
import SwiftData

/// Persistence-side orchestration for weekly plans.
///
/// The analysis and generation themselves are pure; this only decides what gets
/// written to the store, so views never carry that logic.
@MainActor
struct PlanStore {
    let context: ModelContext
    var analyser: WeeklyAnalyser = WeeklyAnalyser()
    var generator: WeeklyPlanGenerator = WeeklyPlanGenerator()

    func hasWeek(after plan: WeeklyPlan) -> Bool {
        let target = plan.weekNumber + 1
        let descriptor = FetchDescriptor<WeeklyPlan>(
            predicate: #Predicate { $0.weekNumber == target }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Returns `nil` when the following week already exists, so tapping twice
    /// cannot produce two week 2s.
    @discardableResult
    func generateNextWeek(after plan: WeeklyPlan) -> WeeklyPlan? {
        guard !hasWeek(after: plan) else { return nil }

        let next = generator.generate(after: plan, analysis: analyser.analyse(plan))
        plan.status = .completed
        context.insert(next)
        try? context.save()
        return next
    }
}
