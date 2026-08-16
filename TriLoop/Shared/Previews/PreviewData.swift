import SwiftData
import SwiftUI

/// Preview/in-memory container seeded with Week 1, so previews render real data.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        do {
            let container = try TriLoopModelContainer.make(inMemory: true)
            SeedDataInstaller.installIfNeeded(in: container.mainContext)
            return container
        } catch {
            fatalError("Failed to build the preview container: \(error)")
        }
    }()

    static var plan: WeeklyPlan {
        let descriptor = FetchDescriptor<WeeklyPlan>()
        guard let plan = try? container.mainContext.fetch(descriptor).first else {
            fatalError("Preview container has no seeded plan.")
        }
        return plan
    }

    static func workout(_ discipline: Discipline) -> PlannedWorkout {
        guard let workout = plan.orderedWorkouts.first(where: { $0.discipline == discipline }) else {
            fatalError("Preview plan has no \(discipline.rawValue) workout.")
        }
        return workout
    }

    /// A date inside the seeded week, for previewing the "today" state.
    static var sampleToday: Date { plan.startDate }
}
