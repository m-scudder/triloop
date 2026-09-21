import Foundation
import Testing

@testable import Athevia

@Suite("Watch workout transfer")
@MainActor
struct WatchWorkoutTransferTests {
    @Test("Shared watch payload round-trips through JSON")
    func payloadRoundTrip() throws {
        let step = WatchWorkoutStepPayload(
            id: UUID(),
            kind: .work,
            title: "Steady run",
            instructions: "Stay relaxed",
            durationSeconds: 600,
            distanceMeters: nil,
            targetIntensity: .steady,
            repeatCount: nil,
            children: []
        )
        let workout = WatchWorkoutPayload(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            discipline: .running,
            title: "Easy Run",
            goal: "Aerobic",
            estimatedDurationSeconds: 600,
            estimatedDistanceMeters: nil,
            status: .planned,
            steps: [step]
        )
        let payload = WatchWorkoutListPayload(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            weekStart: Date(timeIntervalSince1970: 1_699_900_000),
            workouts: [workout]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WatchWorkoutListPayload.self, from: data)

        #expect(decoded == payload)
    }

    @Test("Watch fingerprint changes when a workout prescription changes")
    func fingerprintTracksWorkoutEdits() {
        let workout = PlannedWorkout(
            date: .now,
            discipline: .running,
            title: "Intervals",
            steps: [
                WorkoutStep(
                    order: 0,
                    kind: .work,
                    title: "Run",
                    durationSeconds: 60,
                    targetIntensity: .hard
                )
            ]
        )
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start)!

        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: start,
            endDate: end,
            workouts: [workout]
        )

        let before = WatchAppPlanSync.fingerprint(plan)
        workout.steps[0].durationSeconds = 90
        let after = WatchAppPlanSync.fingerprint(plan)

        #expect(before != after)
    }
}
