import Foundation
import SwiftData
import Testing
@testable import TriLoop

/// §10.3.13 and §10.3.15: an athlete's workouts can be saved, edited, copied and
/// removed without any of it reaching training that has already happened.
@MainActor
@Suite("Custom workout lifecycle")
struct WorkoutTemplateLifecycleTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: TriLoopSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func draft() -> WorkoutDraft {
        WorkoutDraft(
            sport: .cycling,
            name: "My Ride",
            category: .endurance,
            blocks: [WorkoutDraftBlock(kind: .work, title: "Steady", durationSeconds: 1_800)],
            targetRPE: RPERange(3, 4)
        )
    }

    @Test("Saving twice updates one workout rather than making two")
    func savingTwiceUpdates() throws {
        let container = try container()
        let context = ModelContext(container)

        let first = draft()
        context.insert(StoredWorkoutTemplate(first.template))
        try context.save()

        var edited = WorkoutDraft(editing: first.template)
        edited.name = "My Longer Ride"

        let existing = try #require(
            try context.fetch(FetchDescriptor<StoredWorkoutTemplate>()).first { $0.id == edited.id }
        )
        existing.apply(edited.template)
        try context.save()

        let reopened = ModelContext(container)
        let all = try reopened.fetch(FetchDescriptor<StoredWorkoutTemplate>())
        #expect(all.count == 1)
        #expect(all.first?.name == "My Longer Ride")
    }

    @Test("A duplicate is independent of the workout it came from")
    func duplicateIsIndependent() throws {
        let context = ModelContext(try container())
        let original = draft().template

        let copy = WorkoutTemplate(
            sport: original.sport,
            name: "\(original.name) copy",
            category: original.category,
            purpose: original.purpose,
            structure: original.structure,
            targetRPE: original.targetRPE
        )
        let storedOriginal = StoredWorkoutTemplate(original)
        let storedCopy = StoredWorkoutTemplate(copy)
        context.insert(storedOriginal)
        context.insert(storedCopy)

        #expect(storedCopy.id != storedOriginal.id)

        var editedCopy = WorkoutDraft(editing: copy)
        editedCopy.blocks = [WorkoutDraftBlock(kind: .work, title: "Different", durationSeconds: 600)]
        storedCopy.apply(editedCopy.template)

        #expect(storedOriginal.structure == original.structure)
    }

    @Test("Editing a saved workout leaves sessions already planned from it alone")
    func editingDoesNotReachPlannedSessions() throws {
        let context = ModelContext(try container())
        let template = draft().template
        let stored = StoredWorkoutTemplate(template)
        context.insert(stored)

        let planned = WorkoutTemplateScheduler.workout(from: template, on: .now)
        context.insert(planned)
        let before = WorkoutStructure(steps: planned.steps)

        var edited = WorkoutDraft(editing: template)
        edited.blocks = [WorkoutDraftBlock(kind: .work, title: "Changed", durationSeconds: 60)]
        stored.apply(edited.template)

        #expect(WorkoutStructure(steps: planned.steps) == before)
        #expect(planned.title == "My Ride")
    }

    @Test("Effort presets survive a round trip")
    func effortPresets() {
        for preset in EffortPreset.allCases {
            #expect(EffortPreset(preset.range) == preset)
        }
        // An unset effort opens on something sensible rather than crashing.
        #expect(EffortPreset(nil) == .easy)
    }

    @Test("A saved workout can be added to the plan and sent to Apple Watch")
    func savedWorkoutIsUsable() throws {
        let template = draft().template

        #expect(WorkoutTemplateScheduler.workout(from: template, on: .now).origin == .custom)
        #expect(WorkoutPlanBuilder.compatibility(for: template).isSupported)
    }
}
