import Foundation

/// Development seed for the athlete's actual first training week.
///
/// The dates are data, not architecture: `startDate` is injectable so the
/// Phase 4 generator and tests can build weeks anywhere on the calendar.
enum SeedWeekOne {

    /// Monday 17 August 2026, in the current calendar's time zone.
    static func defaultStartDate(calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        return calendar.date(from: components) ?? calendar.startOfDay(for: .now)
    }

    static func makeProfile(startDate: Date) -> AthleteProfile {
        AthleteProfile(
            name: "Athlete",
            experienceLevel: .beginner,
            trainingStartDate: startDate
        )
    }

    static func makePlan(
        startDate: Date? = nil,
        calendar: Calendar = .current
    ) -> WeeklyPlan {
        let monday = calendar.startOfDay(for: startDate ?? defaultStartDate(calendar: calendar))

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
        }

        let workouts: [PlannedWorkout] = [
            runWalk(on: day(0), sessionNumber: 1),
            techniqueSwim(on: day(1), sessionNumber: 1),
            recoveryDay(on: day(2)),
            runWalk(on: day(3), sessionNumber: 2),
            techniqueSwim(on: day(4), sessionNumber: 2),
            easyRide(on: day(5)),
            restDay(on: day(6))
        ]

        return WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: day(6),
            status: .active,
            generationReason: "First week. Introductory volume across all three sports, with cycling starting Saturday.",
            workouts: workouts
        )
    }

    // MARK: - Sessions

    private static func runWalk(on date: Date, sessionNumber: Int) -> PlannedWorkout {
        let steps: [WorkoutStep] = [
            .warmUp(order: 0, title: "Brisk walk", durationSeconds: 5 * 60),
            .repeating(
                order: 1,
                title: "Run / walk intervals",
                count: 6,
                children: [
                    WorkoutStep(
                        order: 0,
                        kind: .work,
                        title: "Easy run",
                        instructions: "Conversational. If you cannot speak, slow down.",
                        durationSeconds: 60,
                        targetIntensity: .easy
                    ),
                    WorkoutStep(
                        order: 1,
                        kind: .recovery,
                        title: "Walk",
                        durationSeconds: 120,
                        targetIntensity: .veryEasy
                    )
                ]
            ),
            .cooldown(order: 2, title: "Easy walk", durationSeconds: 5 * 60)
        ]

        return PlannedWorkout(
            date: date,
            discipline: .running,
            title: "Beginner Run / Walk #\(sessionNumber)",
            goal: "Build running tolerance while keeping impact low.",
            targetRPE: RPERange(3, 4),
            steps: steps
        )
    }

    private static func techniqueSwim(on date: Date, sessionNumber: Int) -> PlannedWorkout {
        let steps: [WorkoutStep] = [
            .warmUp(
                order: 0,
                title: "4 × 25 m easy",
                distanceMeters: 100,
                instructions: "Any stroke. Loosen up and get comfortable in the water."
            ),
            WorkoutStep(
                order: 1,
                kind: .work,
                title: "4 × 25 m breathing focus",
                instructions: "Exhale fully underwater. Rest 30–60 sec between lengths as needed.",
                distanceMeters: 100,
                targetIntensity: .easy
            ),
            WorkoutStep(
                order: 2,
                kind: .work,
                title: "4 × 25 m relaxed freestyle",
                instructions: "Long, unhurried strokes. Technique over speed. Rest 30–60 sec as needed.",
                distanceMeters: 100,
                targetIntensity: .easy
            )
        ]

        return PlannedWorkout(
            date: date,
            discipline: .swimming,
            title: "Technique Swim #\(sessionNumber)",
            goal: "Get comfortable breathing and moving efficiently in the water.",
            targetRPE: RPERange(3, 5),
            targetDistanceMeters: 300,
            steps: steps
        )
    }

    private static func easyRide(on date: Date) -> PlannedWorkout {
        let steps: [WorkoutStep] = [
            .warmUp(order: 0, title: "Easy spinning", durationSeconds: 5 * 60),
            WorkoutStep(
                order: 1,
                kind: .work,
                title: "Comfortable riding",
                instructions: "Flat or gently rolling. Keep the effort easy enough to hold a conversation.",
                durationSeconds: 20 * 60,
                targetIntensity: .easy
            ),
            .cooldown(order: 2, title: "Easy spinning", durationSeconds: 5 * 60)
        ]

        return PlannedWorkout(
            date: date,
            discipline: .cycling,
            title: "Easy Endurance Ride",
            goal: "First ride on the new bike. Get used to handling, position and gearing.",
            targetRPE: RPERange(3, 4),
            steps: steps
        )
    }

    private static func recoveryDay(on date: Date) -> PlannedWorkout {
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
            goal: "Let the first run and swim settle before repeating them.",
            steps: steps
        )
    }

    private static func restDay(on date: Date) -> PlannedWorkout {
        PlannedWorkout(
            date: date,
            discipline: .rest,
            title: "Rest",
            goal: "Full rest. Adaptation happens now, not during the sessions."
        )
    }
}
