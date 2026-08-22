import Foundation
import SwiftData
import Testing
@testable import TriLoop

/// §10.2.2: one structure concept, two representations. The value mirror and
/// the persisted rows must agree, or a template and the workout it produces
/// would describe different sessions.
@MainActor
@Suite("Workout structure")
struct WorkoutStructureTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: TriLoopSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Warm-up, a 4 × interval block, then a cool-down.
    private func structure() -> WorkoutStructure {
        WorkoutStructure([
            WorkoutBlock(kind: .warmUp, title: "Brisk walk", durationSeconds: 300, targetIntensity: .veryEasy),
            WorkoutBlock(
                kind: .repeatBlock,
                title: "Intervals",
                repeatCount: 4,
                children: [
                    WorkoutBlock(kind: .work, title: "Run", durationSeconds: 300, targetIntensity: .easy),
                    WorkoutBlock(kind: .recovery, title: "Walk", durationSeconds: 60)
                ]
            ),
            WorkoutBlock(kind: .cooldown, title: "Easy walk", durationSeconds: 300, targetIntensity: .veryEasy)
        ])
    }

    @Test("A structure survives becoming persisted steps and coming back")
    func roundTrip() throws {
        let context = ModelContext(try container())
        let original = structure()

        let steps = original.makeSteps()
        steps.forEach(context.insert)

        #expect(WorkoutStructure(steps: steps) == original)
    }

    @Test("Order comes from position, not a stored index")
    func orderIsPositional() {
        let steps = structure().makeSteps()

        #expect(steps.map(\.order) == [0, 1, 2])
        #expect(steps.map(\.kind) == [.warmUp, .repeatBlock, .cooldown])
        #expect(steps[1].orderedChildren.map(\.order) == [0, 1])
    }

    @Test("Steps read back in order even when stored shuffled")
    func readsBackInOrder() {
        let steps = structure().makeSteps()
        let shuffled = [steps[2], steps[0], steps[1]]

        #expect(WorkoutStructure(steps: shuffled).blocks.map(\.kind) == [.warmUp, .repeatBlock, .cooldown])
    }

    @Test("Two workouts from one structure share no identifiers")
    func instancesAreIndependent() {
        let structure = structure()
        let first = structure.makeSteps()
        let second = structure.makeSteps()

        #expect(Set(first.map(\.id)).isDisjoint(with: Set(second.map(\.id))))
    }

    @Test("Totals expand repeats the same way the persisted step does")
    func totalsMatchPersistedSteps() {
        let structure = structure()
        let steps = structure.makeSteps()

        // 300 warm-up + 4 × (300 + 60) + 300 cool-down.
        #expect(structure.totalDurationSeconds == 2_040)

        let fromSteps = steps.compactMap(\.totalDurationSeconds).reduce(0, +)
        #expect(structure.totalDurationSeconds == fromSteps)
    }

    @Test("Swim distances expand repeats too")
    func swimDistances() {
        let swim = WorkoutStructure([
            WorkoutBlock(kind: .warmUp, title: "Easy", distanceMeters: 200),
            WorkoutBlock(
                kind: .repeatBlock,
                title: "Set",
                repeatCount: 4,
                children: [WorkoutBlock(kind: .work, title: "Freestyle", distanceMeters: 50)]
            )
        ])

        #expect(swim.totalDistanceMeters == 400)
        #expect(swim.totalDurationSeconds == nil)
    }

    @Test("A structure of only warm-up and cool-down has nothing to execute")
    func executableBlocks() {
        let empty = WorkoutStructure()
        #expect(empty.isEmpty)
        #expect(!empty.hasExecutableBlock)

        let bookendsOnly = WorkoutStructure([
            WorkoutBlock(kind: .warmUp, title: "Walk", durationSeconds: 300),
            WorkoutBlock(kind: .cooldown, title: "Walk", durationSeconds: 300)
        ])
        #expect(!bookendsOnly.hasExecutableBlock)
        #expect(structure().hasExecutableBlock)
    }

    @Test("A structure encodes and decodes unchanged")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(structure())
        #expect(try JSONDecoder().decode(WorkoutStructure.self, from: data) == structure())
    }
}
