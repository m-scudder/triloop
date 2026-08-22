import Foundation
import Testing
@testable import TriLoop

/// §10.10 and §10.3.14: a draft is transient, and cloning a built-in must leave
/// the original exactly as it shipped.
@Suite("Custom workout draft")
struct WorkoutDraftTests {

    private func runDraft() -> WorkoutDraft {
        WorkoutDraft(
            sport: .running,
            name: "My Tempo",
            category: .tempo,
            blocks: [
                WorkoutDraftBlock(kind: .warmUp, title: "Jog", durationSeconds: 600),
                WorkoutDraftBlock(
                    kind: .repeatBlock,
                    title: "Tempo",
                    repeatCount: 3,
                    children: [
                        WorkoutDraftBlock(kind: .work, title: "Tempo", durationSeconds: 480),
                        WorkoutDraftBlock(kind: .recovery, title: "Jog", durationSeconds: 120)
                    ]
                )
            ],
            targetRPE: RPERange(6, 7)
        )
    }

    // MARK: - Becoming a template

    @Test("A draft becomes an athlete-owned template")
    func draftProducesTemplate() {
        let template = runDraft().template

        #expect(template.source == .athlete)
        #expect(template.name == "My Tempo")
        #expect(template.structure.blocks.count == 2)
        #expect(template.totalDurationSeconds == 2_400)
    }

    @Test("Whitespace around a name is not part of it")
    func namesAreTrimmed() {
        var draft = runDraft()
        draft.name = "  Spaced  "

        #expect(draft.template.name == "Spaced")
    }

    @Test("An empty draft is not saveable")
    func emptyDraftIsInvalid() {
        let draft = WorkoutDraft(sport: .running)

        #expect(!draft.isValid())
        #expect(draft.issues().contains(.missingName))
        #expect(draft.issues().contains(.noExecutableBlock))
    }

    @Test("A complete draft validates")
    func completeDraftIsValid() {
        #expect(runDraft().isValid())
    }

    // MARK: - Editing and cloning

    @Test("Editing keeps the identity, so saving replaces rather than duplicates")
    func editingKeepsIdentity() {
        let original = runDraft().template
        let draft = WorkoutDraft(editing: original)

        #expect(draft.id == original.id)
        #expect(draft.template == original)
    }

    @Test("Customising a built-in clones it under a new identity")
    func customisingClones() throws {
        let builtIn = try #require(WorkoutLibrary.running.first)
        let draft = WorkoutDraft(customising: builtIn)

        #expect(draft.id != builtIn.id)
        #expect(draft.name == "\(builtIn.name) — Custom")
        #expect(draft.template.source == .athlete)
        // The structure is copied, not shared.
        #expect(draft.template.structure == builtIn.structure)
    }

    @Test("Editing a clone cannot reach the built-in it came from")
    func builtInsAreImmutable() throws {
        let builtIn = try #require(WorkoutLibrary.running.first)
        let before = builtIn.structure

        var draft = WorkoutDraft(customising: builtIn)
        draft.blocks.removeAll()
        draft.name = "Something else"

        let after = try #require(WorkoutLibrary.template(id: builtIn.id))
        #expect(after.structure == before)
        #expect(after.name == builtIn.name)
    }

    // MARK: - New blocks

    @Test("A new block opens on the measure the sport actually uses")
    func newBlocksMatchTheSport() {
        let run = WorkoutDraft(sport: .running).newBlock(.work)
        #expect(run.durationSeconds != nil)
        #expect(run.distanceMeters == nil)

        let swim = WorkoutDraft(sport: .swimming).newBlock(.work)
        #expect(swim.distanceMeters != nil)
        #expect(swim.durationSeconds == nil)
    }

    @Test("Rest is counted in seconds even in the pool")
    func restIsAlwaysTime() {
        let rest = WorkoutDraft(sport: .swimming).newBlock(.recovery)

        #expect(rest.durationSeconds != nil)
        #expect(rest.distanceMeters == nil)
    }

    @Test("A new repeat block arrives with something to repeat")
    func newRepeatBlockIsUsable() {
        var draft = WorkoutDraft(sport: .running, name: "Set")
        draft.blocks = [draft.newBlock(.repeatBlock)]

        #expect(draft.blocks[0].children.count == 2)
        #expect(draft.isValid())
    }

    // MARK: - Apple Watch

    @Test("Every built-in workout can be sent to Apple Watch")
    func builtInsAreWatchCompatible() {
        for template in WorkoutLibrary.all {
            #expect(
                WorkoutPlanBuilder.compatibility(for: template).isSupported,
                "\(template.name): \(WorkoutPlanBuilder.compatibility(for: template).reason ?? "")"
            )
        }
    }

    @Test("A custom workout with real steps can be sent")
    func customWorkoutIsCompatible() {
        #expect(WorkoutPlanBuilder.compatibility(for: runDraft().template).isSupported)
    }

    @Test("A workout with nothing in it is reported as unsendable, not crashed on")
    func emptyWorkoutIsUnsupported() {
        let empty = WorkoutTemplate(
            sport: .running,
            name: "Empty",
            category: .easy,
            structure: WorkoutStructure()
        )

        let compatibility = WorkoutPlanBuilder.compatibility(for: empty)
        #expect(!compatibility.isSupported)
        #expect(compatibility.reason != nil)
    }
}
