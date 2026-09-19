import Foundation
import SwiftData
import Testing
@testable import Athevia

/// §10.2.5 and §10.3.13: provenance and athlete-owned templates have to survive
/// being written to the store, or the distinction is only a runtime opinion.
@MainActor
@Suite("Workout provenance and stored templates")
struct WorkoutProvenanceTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: AtheviaSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func template() -> WorkoutTemplate {
        WorkoutTemplate(
            sport: .running,
            name: "My Tempo",
            category: .tempo,
            purpose: "Hold a firm effort.",
            structure: WorkoutStructure([
                .warmUp("Jog", seconds: 600),
                .repeating("Tempo", times: 3, [
                    .work("Tempo", seconds: 480, intensity: .moderate),
                    .recovery("Jog", seconds: 120)
                ]),
                .coolDown("Jog", seconds: 600)
            ]),
            targetRPE: RPERange(6, 7)
        )
    }

    // MARK: - Provenance

    @Test("A workout built without saying so is Athevia's own")
    func defaultOriginIsGenerated() {
        let workout = PlannedWorkout(date: .now, discipline: .running, title: "Run")

        #expect(workout.origin == .generated)
        #expect(workout.origin.isPrescribedByAthevia)
    }

    @Test("Only a generated session counts as Athevia's prescription")
    func onlyGeneratedIsPrescribed() {
        #expect(WorkoutOrigin.generated.isPrescribedByAthevia)
        #expect(!WorkoutOrigin.library.isPrescribedByAthevia)
        #expect(!WorkoutOrigin.custom.isPrescribedByAthevia)
        #expect(!WorkoutOrigin.imported.isPrescribedByAthevia)
    }

    @Test("Origin survives being stored and read back")
    func originPersists() throws {
        let container = try container()
        let context = ModelContext(container)

        let workout = PlannedWorkout(date: .now, discipline: .cycling, title: "Ride", origin: .library)
        context.insert(workout)
        try context.save()

        let reopened = ModelContext(container)
        let stored = try reopened.fetch(FetchDescriptor<PlannedWorkout>())

        #expect(stored.count == 1)
        #expect(stored.first?.origin == .library)
    }

    @Test("Everything the engine builds is still marked as generated")
    func prescribedSessionsAreGenerated() {
        let session = PrescribedSessions.session(.running, on: .now, parameters: TrainingParameters())

        #expect(session.origin == .generated)
    }

    // MARK: - Stored templates

    @Test("An athlete's template survives the store unchanged")
    func templatePersists() throws {
        let container = try container()
        let context = ModelContext(container)
        let original = template()

        context.insert(StoredWorkoutTemplate(original))
        try context.save()

        let reopened = ModelContext(container)
        let stored = try #require(try reopened.fetch(FetchDescriptor<StoredWorkoutTemplate>()).first)

        #expect(stored.template == original)
        #expect(stored.template.structure == original.structure)
    }

    @Test("A stored template is always the athlete's, never a built-in")
    func storedTemplatesAreAthleteOwned() throws {
        let context = ModelContext(try container())
        // Even seeded from a built-in, what comes back is the athlete's copy.
        let builtIn = try #require(WorkoutLibrary.running.first)

        let stored = StoredWorkoutTemplate(builtIn)
        context.insert(stored)

        #expect(stored.template.source == .athlete)
        #expect(stored.template.source.isEditable)
    }

    @Test("Editing a template does not touch a workout already made from it")
    func editingDoesNotReachIntoPlannedWorkouts() throws {
        let context = ModelContext(try container())
        let stored = StoredWorkoutTemplate(template())
        context.insert(stored)

        let workout = PlannedWorkout(
            date: .now,
            discipline: .running,
            title: stored.name,
            origin: .custom,
            steps: stored.structure.makeSteps()
        )
        context.insert(workout)
        let before = WorkoutStructure(steps: workout.steps)

        var edited = stored.template
        edited.name = "Something else"
        edited.structure = WorkoutStructure([.work("Easy", seconds: 600)])
        stored.apply(edited)

        #expect(stored.name == "Something else")
        #expect(WorkoutStructure(steps: workout.steps) == before)
        #expect(workout.title == "My Tempo")
    }

    @Test("Deleting a template leaves the training it produced alone")
    func deletingDoesNotRemoveHistory() throws {
        let container = try container()
        let context = ModelContext(container)

        let stored = StoredWorkoutTemplate(template())
        context.insert(stored)

        let workout = PlannedWorkout(
            date: .now,
            discipline: .running,
            title: "My Tempo",
            origin: .custom,
            steps: stored.structure.makeSteps()
        )
        context.insert(workout)
        try context.save()

        context.delete(stored)
        try context.save()

        let reopened = ModelContext(container)
        #expect(try reopened.fetch(FetchDescriptor<StoredWorkoutTemplate>()).isEmpty)

        let survivors = try reopened.fetch(FetchDescriptor<PlannedWorkout>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.steps.count == 3)
    }
}
