import Foundation
import Testing

@testable import Athevia

@Suite("Workout naming")
struct WorkoutNamingTests {
    private func journey(_ phase: TrainingPhase) -> TrainingJourney {
        TrainingJourney(
            phase: phase,
            weeksRemaining: 8,
            readiness: EventReadiness(
                status: .building,
                sports: []
            ),
            weeklyObjectives: [],
            sportPriorities: []
        )
    }

    @Test("Non-event plans use only the sport name")
    func normalPlansUseSportNames() {
        let builder = PhaseWorkoutPrescriptionBuilder()
        let objective = TrainingObjective(kind: .generalFitness)
        let parameters = TrainingParameters()

        let running = builder.workout(
            sport: .running,
            on: .now,
            parameters: parameters,
            journey: journey(.build),
            objective: objective,
            capability: nil
        )
        let cycling = builder.workout(
            sport: .cycling,
            on: .now,
            parameters: parameters,
            journey: journey(.build),
            objective: objective,
            capability: nil
        )
        let swimming = builder.workout(
            sport: .swimming,
            on: .now,
            parameters: parameters,
            journey: journey(.build),
            objective: objective,
            capability: nil
        )

        #expect(running.title == "Running")
        #expect(cycling.title == "Cycling")
        #expect(swimming.title == "Swimming")
    }

    @Test("Event plans use only the core athletics vocabulary")
    func eventPlansUseGenericVocabulary() {
        let builder = PhaseWorkoutPrescriptionBuilder()
        let objective = TrainingObjective.event(
            sport: .running,
            distance: EventDistance(kind: .run10K)
        )

        let easy = builder.workout(
            sport: .running,
            on: .now,
            parameters: TrainingParameters(),
            journey: journey(.build),
            objective: objective,
            capability: nil,
            sportOrdinal: 0
        )

        let endurance = builder.workout(
            sport: .running,
            on: .now,
            parameters: TrainingParameters(),
            journey: journey(.build),
            objective: objective,
            capability: nil,
            sportOrdinal: 1
        )

        let racePace = builder.workout(
            sport: .running,
            on: .now,
            parameters: TrainingParameters(),
            journey: journey(.specific),
            objective: objective,
            capability: nil,
            sportOrdinal: 2
        )

        #expect(easy.title == "Easy Running")
        #expect(endurance.title == "Endurance Running")
        #expect(racePace.title == "Race Pace Running")
    }

    @Test("Swimming event plan uses technique as the foundation vocabulary")
    func eventSwimmingUsesTechniqueVocabulary() {
        let workout = PhaseWorkoutPrescriptionBuilder().workout(
            sport: .swimming,
            on: .now,
            parameters: TrainingParameters(),
            journey: journey(.foundation),
            objective: .event(
                sport: .swimming,
                distance: EventDistance(kind: .swimming1K)
            ),
            capability: nil
        )

        #expect(workout.title == "Technique Swimming")
    }

    @Test("Multisport titles use the shared race vocabulary")
    func multisportUsesGenericVocabulary() {
        let parameters = TrainingParameters()
        let prescription = BrickPrescription(
            bikeSeconds: 1_800,
            transitionSeconds: 300,
            runSeconds: 600,
            targetIntensity: .easy
        )

        let brick = MultisportPrescribedSessions.brick(
            on: .now,
            parameters: parameters,
            prescription: prescription
        )
        let simulation = MultisportPrescribedSessions.raceSimulation(
            on: .now,
            parameters: parameters,
            prescription: prescription
        )

        #expect(brick.title == "Brick")
        #expect(simulation.title == "Race Simulation")
    }
}
