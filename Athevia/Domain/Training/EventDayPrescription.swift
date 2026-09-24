import Foundation

enum EventDayPrescription {
    static func workout(
        for event: AthleteEventGoal,
        on date: Date
    ) -> PlannedWorkout {
        switch event.sport {
        case .running:
            return singleSport(
                discipline: .running,
                title: event.displayName,
                goal: "Event day. Use the preparation you have practised; this replaces normal training today.",
                distanceMeters: event.distance?.components.runMeters,
                on: date
            )

        case .cycling:
            return singleSport(
                discipline: .cycling,
                title: event.displayName,
                goal: "Event day. Use the preparation you have practised; this replaces normal training today.",
                distanceMeters: event.distance?.components.bikeMeters,
                on: date
            )

        case .swimming:
            return singleSport(
                discipline: .swimming,
                title: event.displayName,
                goal: "Event day. Use the preparation you have practised; this replaces normal training today.",
                distanceMeters: event.distance?.components.swimMeters,
                on: date
            )

        case .triathlon:
            let components = event.distance?.components ?? EventDistanceComponents()
            var steps: [WorkoutStep] = []
            var order = 0

            if let swim = components.swimMeters {
                steps.append(WorkoutStep(
                    order: order,
                    kind: .swimmingSegment,
                    title: "Swim",
                    instructions: "Use your planned event effort.",
                    distanceMeters: swim,
                    targetIntensity: .steady
                ))
                order += 1
                steps.append(WorkoutStep(
                    order: order,
                    kind: .transition,
                    title: "Transition 1",
                    instructions: "Move safely and deliberately through transition.",
                    durationSeconds: 5 * 60,
                    targetIntensity: .veryEasy
                ))
                order += 1
            }

            if let bike = components.bikeMeters {
                steps.append(WorkoutStep(
                    order: order,
                    kind: .cyclingSegment,
                    title: "Bike",
                    instructions: "Settle into the event effort you practised.",
                    distanceMeters: bike,
                    targetIntensity: .steady
                ))
                order += 1
                steps.append(WorkoutStep(
                    order: order,
                    kind: .transition,
                    title: "Transition 2",
                    instructions: "Dismount safely and start the run under control.",
                    durationSeconds: 5 * 60,
                    targetIntensity: .veryEasy
                ))
                order += 1
            }

            if let run = components.runMeters {
                steps.append(WorkoutStep(
                    order: order,
                    kind: .runningSegment,
                    title: "Run",
                    instructions: "Start controlled and use the pacing you practised.",
                    distanceMeters: run,
                    targetIntensity: .steady
                ))
            }

            return PlannedWorkout(
                date: date,
                discipline: .multisport,
                title: event.displayName,
                goal: "Event day. This is today's primary activity; no normal progressive training is prescribed.",
                targetRPE: nil,
                steps: steps
            )
        }
    }

    private static func singleSport(
        discipline: Discipline,
        title: String,
        goal: String,
        distanceMeters: Double?,
        on date: Date
    ) -> PlannedWorkout {
        let steps = [
            WorkoutStep(
                order: 0,
                kind: .work,
                title: title,
                instructions: "Use familiar pacing and equipment. Do not introduce new training stress.",
                distanceMeters: distanceMeters,
                targetIntensity: .steady
            )
        ]
        return PlannedWorkout(
            date: date,
            discipline: discipline,
            title: title,
            goal: goal,
            targetRPE: nil,
            targetDistanceMeters: distanceMeters,
            steps: steps
        )
    }
}
