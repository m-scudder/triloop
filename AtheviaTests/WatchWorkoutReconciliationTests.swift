import Foundation
import Testing

@testable import Athevia

@Suite("Watch workout reconciliation")
@MainActor
struct WatchWorkoutReconciliationTests {
    @Test("Athevia Watch UUID wins over duration heuristics")
    func exactIdentityWins() {
        let calendar = Calendar(identifier: .gregorian)
        let plannedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let workoutID = UUID()

        let planned = PlannedWorkout(
            id: workoutID,
            date: plannedDate,
            discipline: .running,
            title: "Long Run",
            prescribedDurationSeconds: 3_600
        )

        let imported = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: plannedDate.addingTimeInterval(86_400),
            endDate: plannedDate.addingTimeInterval(86_520),
            duration: 120,
            distanceMeters: 200,
            plannedWorkoutID: workoutID,
            source: "com.mayankagarwal.athevia.watchkitapp"
        )

        let result = WorkoutMatcher(calendar: calendar).match(
            planned: [planned],
            with: [imported],
            asOf: imported.endDate.addingTimeInterval(60)
        )

        #expect(result.matches.count == 1)
        #expect(result.matches.first?.planned.id == workoutID)
        #expect(result.matches.first?.imported.plannedWorkoutID == workoutID)
    }
}
