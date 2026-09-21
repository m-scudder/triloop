#if DEBUG
import Foundation

enum WatchSimulatorFixture {
    static func payload(now: Date = .now, calendar: Calendar = .current) -> WatchWorkoutListPayload {
        let today = calendar.startOfDay(for: now)

        let run = WatchWorkoutPayload(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            date: today,
            discipline: .running,
            title: "Interval Run",
            goal: "Build controlled speed",
            estimatedDurationSeconds: 210,
            estimatedDistanceMeters: nil,
            status: .planned,
            steps: [
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111101")!,
                    kind: .warmUp,
                    title: "Warm-up",
                    instructions: "Easy running",
                    durationSeconds: 30,
                    distanceMeters: nil,
                    targetIntensity: .veryEasy,
                    repeatCount: nil,
                    children: []
                ),
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111102")!,
                    kind: .repeatBlock,
                    title: "Intervals",
                    instructions: nil,
                    durationSeconds: nil,
                    distanceMeters: nil,
                    targetIntensity: nil,
                    repeatCount: 3,
                    children: [
                        WatchWorkoutStepPayload(
                            id: UUID(uuidString: "11111111-1111-1111-1111-111111111103")!,
                            kind: .work,
                            title: "Run hard",
                            instructions: "Strong but controlled",
                            durationSeconds: 30,
                            distanceMeters: nil,
                            targetIntensity: .hard,
                            repeatCount: nil,
                            children: []
                        ),
                        WatchWorkoutStepPayload(
                            id: UUID(uuidString: "11111111-1111-1111-1111-111111111104")!,
                            kind: .recovery,
                            title: "Easy recovery",
                            instructions: "Jog or walk",
                            durationSeconds: 20,
                            distanceMeters: nil,
                            targetIntensity: .easy,
                            repeatCount: nil,
                            children: []
                        )
                    ]
                ),
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111105")!,
                    kind: .cooldown,
                    title: "Cool-down",
                    instructions: "Easy running",
                    durationSeconds: 30,
                    distanceMeters: nil,
                    targetIntensity: .veryEasy,
                    repeatCount: nil,
                    children: []
                )
            ]
        )

        let cycleDate = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let cycle = WatchWorkoutPayload(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            date: cycleDate,
            discipline: .cycling,
            title: "Endurance Ride",
            goal: "Aerobic endurance",
            estimatedDurationSeconds: 180,
            estimatedDistanceMeters: nil,
            status: .planned,
            steps: [
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222201")!,
                    kind: .warmUp,
                    title: "Easy spin",
                    instructions: nil,
                    durationSeconds: 30,
                    distanceMeters: nil,
                    targetIntensity: .easy,
                    repeatCount: nil,
                    children: []
                ),
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222202")!,
                    kind: .work,
                    title: "Steady ride",
                    instructions: "Smooth cadence",
                    durationSeconds: 120,
                    distanceMeters: nil,
                    targetIntensity: .steady,
                    repeatCount: nil,
                    children: []
                ),
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222203")!,
                    kind: .cooldown,
                    title: "Easy spin",
                    instructions: nil,
                    durationSeconds: 30,
                    distanceMeters: nil,
                    targetIntensity: .veryEasy,
                    repeatCount: nil,
                    children: []
                )
            ]
        )

        let swimDate = calendar.date(byAdding: .day, value: 2, to: today) ?? today
        let swim = WatchWorkoutPayload(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: swimDate,
            discipline: .swimming,
            title: "Technique Swim",
            goal: "Relaxed technique",
            estimatedDurationSeconds: nil,
            estimatedDistanceMeters: 300,
            status: .planned,
            steps: [
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333301")!,
                    kind: .warmUp,
                    title: "Warm-up",
                    instructions: "Easy freestyle",
                    durationSeconds: nil,
                    distanceMeters: 100,
                    targetIntensity: .veryEasy,
                    repeatCount: nil,
                    children: []
                ),
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333302")!,
                    kind: .work,
                    title: "Technique",
                    instructions: "Focus on long relaxed strokes",
                    durationSeconds: nil,
                    distanceMeters: 100,
                    targetIntensity: .easy,
                    repeatCount: nil,
                    children: []
                ),
                WatchWorkoutStepPayload(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333303")!,
                    kind: .cooldown,
                    title: "Cool-down",
                    instructions: "Very easy",
                    durationSeconds: nil,
                    distanceMeters: 100,
                    targetIntensity: .veryEasy,
                    repeatCount: nil,
                    children: []
                )
            ]
        )

        return WatchWorkoutListPayload(
            generatedAt: now,
            weekStart: today,
            workouts: [run, cycle, swim]
        )
    }
}
#endif
