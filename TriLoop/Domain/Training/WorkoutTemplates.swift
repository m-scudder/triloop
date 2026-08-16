import Foundation

/// Builds the sessions TriLoop prescribes from a set of `TrainingParameters`.
///
/// Single source of workout construction: the week-one seed and the weekly
/// generator both come through here, so a progression can never drift from the
/// shape of the workout it is progressing.
enum WorkoutTemplates {

    static func runWalk(
        on date: Date,
        sessionNumber: Int,
        parameters: TrainingParameters,
        goal: String? = nil
    ) -> PlannedWorkout {
        let steps: [WorkoutStep] = [
            .warmUp(order: 0, title: "Brisk walk", durationSeconds: parameters.runWarmUpSeconds),
            .repeating(
                order: 1,
                title: "Run / walk intervals",
                count: parameters.runRepeatCount,
                children: [
                    WorkoutStep(
                        order: 0,
                        kind: .work,
                        title: "Easy run",
                        instructions: "Conversational. If you cannot speak, slow down.",
                        durationSeconds: parameters.runIntervalSeconds,
                        targetIntensity: .easy
                    ),
                    WorkoutStep(
                        order: 1,
                        kind: .recovery,
                        title: "Walk",
                        durationSeconds: parameters.runWalkSeconds,
                        targetIntensity: .veryEasy
                    )
                ]
            ),
            .cooldown(order: 2, title: "Easy walk", durationSeconds: parameters.runCooldownSeconds)
        ]

        return PlannedWorkout(
            date: date,
            discipline: .running,
            title: "Beginner Run / Walk #\(sessionNumber)",
            goal: goal ?? "Build running tolerance while keeping impact low.",
            targetRPE: RPERange(3, 4),
            steps: steps
        )
    }

    static func techniqueSwim(
        on date: Date,
        sessionNumber: Int,
        parameters: TrainingParameters,
        goal: String? = nil
    ) -> PlannedWorkout {
        let repeatDistance = parameters.swimRepeatDistanceMeters
        let warmUpMeters = 4 * repeatDistance
        let mainMeters = max(parameters.swimTotalMeters - warmUpMeters, repeatDistance)
        let breathingMeters = rounded(mainMeters / 2, to: repeatDistance)
        let freestyleMeters = mainMeters - breathingMeters
        let rest = Int(parameters.swimRestSeconds)

        let steps: [WorkoutStep] = [
            .warmUp(
                order: 0,
                title: "\(lengths(warmUpMeters, of: repeatDistance)) easy",
                distanceMeters: warmUpMeters,
                instructions: "Any stroke. Loosen up and get comfortable in the water."
            ),
            WorkoutStep(
                order: 1,
                kind: .work,
                title: "\(lengths(breathingMeters, of: repeatDistance)) breathing focus",
                instructions: "Exhale fully underwater. Rest \(rest) sec between lengths.",
                distanceMeters: breathingMeters,
                targetIntensity: .easy
            ),
            WorkoutStep(
                order: 2,
                kind: .work,
                title: "\(lengths(freestyleMeters, of: repeatDistance)) relaxed freestyle",
                instructions: "Long, unhurried strokes. Technique over speed. Rest \(rest) sec.",
                distanceMeters: freestyleMeters,
                targetIntensity: .easy
            )
        ]

        return PlannedWorkout(
            date: date,
            discipline: .swimming,
            title: "Technique Swim #\(sessionNumber)",
            goal: goal ?? "Get comfortable breathing and moving efficiently in the water.",
            targetRPE: RPERange(3, 5),
            targetDistanceMeters: warmUpMeters + breathingMeters + freestyleMeters,
            steps: steps
        )
    }

    static func easyRide(
        on date: Date,
        parameters: TrainingParameters,
        goal: String? = nil
    ) -> PlannedWorkout {
        let steps: [WorkoutStep] = [
            .warmUp(order: 0, title: "Easy spinning", durationSeconds: parameters.rideWarmUpSeconds),
            WorkoutStep(
                order: 1,
                kind: .work,
                title: "Comfortable riding",
                instructions: "Flat or gently rolling. Keep the effort easy enough to hold a conversation.",
                durationSeconds: parameters.rideWorkSeconds,
                targetIntensity: .easy
            ),
            .cooldown(order: 2, title: "Easy spinning", durationSeconds: parameters.rideCooldownSeconds)
        ]

        return PlannedWorkout(
            date: date,
            discipline: .cycling,
            title: "Easy Endurance Ride",
            goal: goal ?? "Build aerobic base at a conversational effort.",
            targetRPE: RPERange(3, 4),
            steps: steps
        )
    }

    static func recoveryDay(on date: Date, goal: String? = nil) -> PlannedWorkout {
        let steps: [WorkoutStep] = [
            WorkoutStep(
                order: 0,
                kind: .recovery,
                title: "Easy walk",
                instructions: "Optional. Keep it relaxed.",
                durationSeconds: 20 * 60,
                targetIntensity: .veryEasy
            ),
            WorkoutStep(
                order: 1,
                kind: .recovery,
                title: "Mobility",
                instructions: "Calves, hips and shoulders. A few minutes is enough.",
                durationSeconds: 10 * 60,
                targetIntensity: .veryEasy
            )
        ]

        return PlannedWorkout(
            date: date,
            discipline: .recovery,
            title: "Recovery",
            goal: goal ?? "Let the week's training settle.",
            steps: steps
        )
    }

    static func restDay(on date: Date) -> PlannedWorkout {
        PlannedWorkout(
            date: date,
            discipline: .rest,
            title: "Rest",
            goal: "Full rest. Adaptation happens now, not during the sessions."
        )
    }

    private static func lengths(_ meters: Double, of repeatDistance: Double) -> String {
        guard repeatDistance > 0 else { return "\(Int(meters)) m" }
        let count = Int((meters / repeatDistance).rounded())
        return "\(count) × \(Int(repeatDistance)) m"
    }

    private static func rounded(_ meters: Double, to repeatDistance: Double) -> Double {
        guard repeatDistance > 0 else { return meters }
        return (meters / repeatDistance).rounded() * repeatDistance
    }
}
