import Foundation

/// Builds the sessions Athevia prescribes from a set of `TrainingParameters`.
///
/// Single source of workout construction: the week-one seed and the weekly
/// generator both come through here, so a progression can never drift from the
/// shape of the workout it is progressing.
enum PrescribedSessions {

    /// Builds whichever session a schedule slot calls for.
    static func session(
        _ discipline: Discipline,
        on date: Date,
        parameters: TrainingParameters,
        goal: String? = nil
    ) -> PlannedWorkout {
        switch discipline {
        case .running: runWalk(on: date, parameters: parameters, goal: goal)
        case .swimming: techniqueSwim(on: date, parameters: parameters, goal: goal)
        case .cycling: easyRide(on: date, parameters: parameters, goal: goal)
        case .multisport:
            MultisportPrescribedSessions.brick(
                on: date,
                parameters: parameters,
                prescription: MultisportTrainingPolicy().brick(parameters: parameters)
            )
        case .recovery: recoveryDay(on: date, goal: goal)
        case .rest: restDay(on: date)
        }
    }

    static func runWalk(
        on date: Date,
        parameters: TrainingParameters,
        goal: String? = nil
    ) -> PlannedWorkout {
        parameters.runIsContinuous
            ? continuousRun(on: date, parameters: parameters, goal: goal)
            : intervalRun(on: date, parameters: parameters, goal: goal)
    }

    private static func continuousRun(
        on date: Date,
        parameters: TrainingParameters,
        goal: String?
    ) -> PlannedWorkout {
        let steps: [WorkoutStep] = [
            WorkoutStep(order: 0, kind: .warmUp, title: "Warm up: brisk walk", instructions: "Start easy, then gradually walk more briskly. Keep your shoulders relaxed and let your arms swing naturally.", durationSeconds: parameters.runWarmUpSeconds, targetIntensity: .veryEasy),
            WorkoutStep(
                order: 1,
                kind: .work,
                title: "Easy run",
                instructions: "No walk breaks. Slow down rather than stopping.",
                durationSeconds: parameters.runContinuousSeconds,
                targetIntensity: .easy
            ),
            WorkoutStep(order: 2, kind: .cooldown, title: "Cool down: easy walk", instructions: "Slow to a relaxed walk. Let your breathing return toward normal; do not stop suddenly.", durationSeconds: parameters.runCooldownSeconds, targetIntensity: .veryEasy)
        ]

        return PlannedWorkout(
            date: date,
            discipline: .running,
            title: "Running",
            goal: goal ?? "Run continuously at a comfortable pace. You should be able to speak in short sentences.",
            targetRPE: RPERange(3, 4),
            steps: steps
        )
    }

    private static func intervalRun(
        on date: Date,
        parameters: TrainingParameters,
        goal: String?
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
            title: "Running",
            goal: goal ?? "Alternate easy running and walking so your body can get used to running safely.",
            targetRPE: RPERange(3, 4),
            steps: steps
        )
    }

    static func techniqueSwim(
        on date: Date,
        parameters: TrainingParameters,
        goal: String? = nil
    ) -> PlannedWorkout {
        let repeatDistance = parameters.swimRepeatDistanceMeters
        // A quarter of the session, not a fixed number of repeats: four 50 m
        // repeats in a long pool would leave a 300 m swim almost entirely
        // warm-up. Never less than one repeat, never more than half the swim.
        let warmUpMeters = min(
            max(rounded(parameters.swimTotalMeters / 4, to: repeatDistance), repeatDistance),
            max(rounded(parameters.swimTotalMeters / 2, to: repeatDistance), repeatDistance)
        )
        let mainMeters = max(parameters.swimTotalMeters - warmUpMeters, repeatDistance)
        let breathingMeters = rounded(mainMeters / 2, to: repeatDistance)
        let strokeMeters = mainMeters - breathingMeters
        let rest = Int(parameters.swimRestSeconds)
        let strokeTitle = parameters.swimStroke == .freestyle
            ? "relaxed freestyle"
            : "relaxed mixed strokes"
        let strokeInstructions = parameters.swimStroke == .freestyle
            ? "Long, unhurried freestyle strokes. Technique over speed. Rest \(rest) sec."
            : "Use comfortable strokes and switch before form breaks down. Technique over speed. Rest \(rest) sec."

        let steps: [WorkoutStep] = [
            .warmUp(
                order: 0,
                title: "\(lengths(warmUpMeters, of: repeatDistance)) easy",
                distanceMeters: warmUpMeters,
                instructions: "Start very easy. Use a comfortable stroke, keep your movements relaxed, and focus on smooth breathing before the main set."
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
                title: "\(lengths(strokeMeters, of: repeatDistance)) \(strokeTitle)",
                instructions: strokeInstructions,
                distanceMeters: strokeMeters,
                targetIntensity: .easy
            )
        ]

        return PlannedWorkout(
            date: date,
            discipline: .swimming,
            title: "Swimming",
            goal: goal ?? "Get comfortable breathing and moving efficiently in the water.",
            targetRPE: RPERange(3, 5),
            targetDistanceMeters: warmUpMeters + breathingMeters + strokeMeters,
            steps: steps
        )
    }

    static func easyRide(
        on date: Date,
        parameters: TrainingParameters,
        goal: String? = nil
    ) -> PlannedWorkout {
        let steps: [WorkoutStep] = [
            WorkoutStep(order: 0, kind: .warmUp, title: "Warm up: easy spinning", instructions: "Use a light gear and pedal smoothly. Start very easy and gradually settle into a comfortable rhythm.", durationSeconds: parameters.rideWarmUpSeconds, targetIntensity: .veryEasy),
            WorkoutStep(
                order: 1,
                kind: .work,
                title: "Comfortable riding",
                instructions: "Flat or gently rolling. Keep the effort easy enough to hold a conversation.",
                durationSeconds: parameters.rideWorkSeconds,
                targetIntensity: .easy
            ),
            WorkoutStep(order: 2, kind: .cooldown, title: "Cool down: easy spinning", instructions: "Shift to a light gear and gradually reduce your effort. Finish with easy, smooth pedaling.", durationSeconds: parameters.rideCooldownSeconds, targetIntensity: .veryEasy)
        ]

        return PlannedWorkout(
            date: date,
            discipline: .cycling,
            title: "Cycling",
            goal: goal ?? "Build stamina with a comfortable ride. You should be able to hold a conversation.",
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
                instructions: "Move slowly through ankle circles, gentle calf stretches, hip rotations and shoulder circles. Hold stretches only to mild tension; never force the range.",
                durationSeconds: 10 * 60,
                targetIntensity: .veryEasy
            )
        ]

        return PlannedWorkout(
            date: date,
            discipline: .recovery,
            title: "Light Movement Day",
            goal: goal ?? "Move gently today so your body can recover and be ready for the next workout.",
            steps: steps
        )
    }

    /// Purposeful low-load activity for a day the athlete said they can train
    /// but where another sport-specific load session would not be appropriate.
    /// It counts as a planned workout while remaining physiologically recovery.
    static func engagementRecoveryDay(
        on date: Date,
        for sports: [Sport]
    ) -> PlannedWorkout {
        let selected = Set(sports)

        if selected == [.swimming] {
            return PlannedWorkout(
                date: date,
                discipline: .recovery,
                title: "Swim Mobility & Recovery",
                goal: "Stay engaged without adding another swim load session. Keep everything gentle.",
                steps: [
                    WorkoutStep(order: 0, kind: .recovery, title: "Easy walk", instructions: "Relaxed movement only.", durationSeconds: 15 * 60, targetIntensity: .veryEasy),
                    WorkoutStep(order: 1, kind: .recovery, title: "Shoulder and upper-back mobility", instructions: "Do slow shoulder circles, arm circles, gentle cross-body shoulder stretches and easy upper-back rotations. Move smoothly and stop before discomfort.", durationSeconds: 15 * 60, targetIntensity: .veryEasy)
                ]
            )
        }

        if selected == [.cycling] {
            return PlannedWorkout(
                date: date,
                discipline: .recovery,
                title: "Cycling Recovery & Mobility",
                goal: "Keep moving while giving your legs a low-load day before the next ride.",
                steps: [
                    WorkoutStep(order: 0, kind: .recovery, title: "Easy walk", instructions: "Keep the effort very easy.", durationSeconds: 20 * 60, targetIntensity: .veryEasy),
                    WorkoutStep(order: 1, kind: .recovery, title: "Hip and leg mobility", instructions: "Do slow hip circles, gentle standing calf stretches and relaxed hamstring stretches. Hold each stretch about 20–30 seconds per side without bouncing.", durationSeconds: 10 * 60, targetIntensity: .veryEasy)
                ]
            )
        }

        if selected == [.running] {
            return PlannedWorkout(
                date: date,
                discipline: .recovery,
                title: "Running Recovery & Mobility",
                goal: "Stay active today without adding another impact-running session.",
                steps: [
                    WorkoutStep(order: 0, kind: .recovery, title: "Easy walk", instructions: "Comfortable walking only.", durationSeconds: 20 * 60, targetIntensity: .veryEasy),
                    WorkoutStep(order: 1, kind: .recovery, title: "Leg mobility", instructions: "Do slow ankle circles, gentle standing calf stretches and easy hip circles. Hold each calf stretch about 20–30 seconds per side; keep every movement comfortable.", durationSeconds: 10 * 60, targetIntensity: .veryEasy)
                ]
            )
        }

        return recoveryDay(
            on: date,
            goal: "Use this available day for gentle movement so you stay consistent without adding unnecessary training load."
        )
    }

    static func restDay(on date: Date, reason: String? = nil) -> PlannedWorkout {
        PlannedWorkout(
            date: date,
            discipline: .rest,
            title: "Rest",
            goal: reason ?? "No workout is scheduled today because this day is outside your selected training availability."
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
