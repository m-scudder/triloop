import Foundation
import Testing
@testable import TriLoop

/// §10.3.11: validation is deterministic and lives in the domain, so the
/// library, the builder and any future import reject the same workouts.
@Suite("Workout template validation")
struct WorkoutTemplateTests {

    private func run(
        name: String = "Easy Run",
        blocks: [WorkoutBlock]
    ) -> WorkoutTemplate {
        WorkoutTemplate(
            sport: .running,
            name: name,
            category: .easy,
            structure: WorkoutStructure(blocks),
            targetRPE: RPERange(3, 4)
        )
    }

    private func swim(_ blocks: [WorkoutBlock]) -> WorkoutTemplate {
        WorkoutTemplate(
            sport: .swimming,
            name: "Technique",
            category: .technique,
            structure: WorkoutStructure(blocks)
        )
    }

    private let work = WorkoutBlock(kind: .work, title: "Easy running", durationSeconds: 1_200)

    @Test("A complete workout has nothing to report")
    func validWorkout() {
        #expect(WorkoutTemplateValidator.isValid(run(blocks: [work])))
    }

    @Test("A workout needs a name")
    func nameRequired() {
        #expect(WorkoutTemplateValidator.issues(in: run(name: "  ", blocks: [work])).contains(.missingName))
    }

    @Test("Warm-up and cool-down alone are not a workout")
    func executableBlockRequired() {
        let bookends = [
            WorkoutBlock(kind: .warmUp, title: "Walk", durationSeconds: 300),
            WorkoutBlock(kind: .cooldown, title: "Walk", durationSeconds: 300)
        ]

        #expect(WorkoutTemplateValidator.issues(in: run(blocks: bookends)).contains(.noExecutableBlock))
    }

    @Test("A block must say how long or how far")
    func targetRequired() {
        let untargeted = WorkoutBlock(kind: .work, title: "Run")

        #expect(
            WorkoutTemplateValidator.issues(in: run(blocks: [untargeted]))
                .contains(.blockWithoutTarget(title: "Run"))
        )
    }

    @Test("Zero and negative targets are rejected")
    func positiveTargets() {
        let noTime = WorkoutBlock(kind: .work, title: "Run", durationSeconds: 0)
        let noDistance = WorkoutBlock(kind: .work, title: "Ride", distanceMeters: -1)

        #expect(
            WorkoutTemplateValidator.issues(in: run(blocks: [noTime]))
                .contains(.nonPositiveDuration(title: "Run"))
        )
        #expect(
            WorkoutTemplateValidator.issues(in: run(blocks: [noDistance]))
                .contains(.nonPositiveDistance(title: "Ride"))
        )
    }

    @Test("A repeat needs a count above one and something to repeat")
    func repeatBlocks() {
        let once = WorkoutBlock(kind: .repeatBlock, title: "Set", repeatCount: 1, children: [work])
        let empty = WorkoutBlock(kind: .repeatBlock, title: "Set", repeatCount: 4)

        #expect(
            WorkoutTemplateValidator.issues(in: run(blocks: [once]))
                .contains(.invalidRepeatCount(title: "Set"))
        )
        #expect(
            WorkoutTemplateValidator.issues(in: run(blocks: [empty]))
                .contains(.emptyRepeatBlock(title: "Set"))
        )
    }

    @Test("A repeat block itself needs no target, but its children do")
    func repeatChildrenAreChecked() {
        let valid = WorkoutBlock(kind: .repeatBlock, title: "Set", repeatCount: 4, children: [work])
        #expect(WorkoutTemplateValidator.isValid(run(blocks: [valid])))

        let untargetedChild = WorkoutBlock(
            kind: .repeatBlock,
            title: "Set",
            repeatCount: 4,
            children: [WorkoutBlock(kind: .work, title: "Run")]
        )
        #expect(
            WorkoutTemplateValidator.issues(in: run(blocks: [untargetedChild]))
                .contains(.blockWithoutTarget(title: "Run"))
        )
    }

    @Test("Swim distances must be whole lengths of the athlete's pool")
    func swimGeometry() {
        let template = swim([WorkoutBlock(kind: .work, title: "Freestyle", distanceMeters: 60)])

        #expect(
            WorkoutTemplateValidator.issues(in: template, poolLengthMeters: 25)
                .contains(.swimDistanceOffPoolLength(title: "Freestyle", meters: 60))
        )
        // 60 m is three lengths of a 20 m pool.
        #expect(WorkoutTemplateValidator.isValid(template, poolLengthMeters: 20))
    }

    @Test("Pool geometry is only checked when a pool is known")
    func swimGeometryNeedsAPool() {
        let template = swim([WorkoutBlock(kind: .work, title: "Freestyle", distanceMeters: 60)])

        #expect(WorkoutTemplateValidator.isValid(template))
    }

    @Test("Running distances are not held to pool geometry")
    func poolGeometryIsSwimmingOnly() {
        let template = run(blocks: [WorkoutBlock(kind: .work, title: "Run", distanceMeters: 5_030)])

        #expect(WorkoutTemplateValidator.isValid(template, poolLengthMeters: 25))
    }

    @Test("A built-in template is not editable and an athlete's is")
    func sourceDecidesEditability() {
        #expect(!WorkoutTemplateSource.triLoop.isEditable)
        #expect(WorkoutTemplateSource.athlete.isEditable)
    }

    @Test("A template encodes and decodes unchanged")
    func codableRoundTrip() throws {
        let template = run(blocks: [work])
        let data = try JSONEncoder().encode(template)

        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: data) == template)
    }
}
