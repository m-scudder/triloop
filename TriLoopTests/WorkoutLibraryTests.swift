import Foundation
import Testing
@testable import TriLoop

/// §10.2.6: built-ins are content, so the tests are about them being usable and
/// stable rather than about any one session's design.
@Suite("Workout library")
struct WorkoutLibraryTests {

    @Test("Every built-in workout validates")
    func allTemplatesAreValid() {
        for template in WorkoutLibrary.all {
            let issues = WorkoutTemplateValidator.issues(in: template)
            #expect(issues.isEmpty, "\(template.name): \(issues.map(\.message))")
        }
    }

    @Test("Every swim works in both a 25 m and a 50 m pool")
    func swimsFitCommonPools() {
        for template in WorkoutLibrary.swimming {
            for poolLength in [25.0, 50.0] {
                let issues = WorkoutTemplateValidator.issues(in: template, poolLengthMeters: poolLength)
                #expect(issues.isEmpty, "\(template.name) in \(Int(poolLength))m: \(issues.map(\.message))")
            }
        }
    }

    @Test("Identifiers are unique and permanent")
    func identifiersAreStable() {
        let ids = WorkoutLibrary.all.map(\.id)
        #expect(Set(ids).count == ids.count)

        // Reading twice must give the same identity, or a planned workout could
        // not record where it came from.
        #expect(WorkoutLibrary.all.map(\.id) == WorkoutLibrary.all.map(\.id))
        #expect(WorkoutLibrary.template(id: ids[0])?.id == ids[0])
    }

    @Test("Every sport has a library")
    func everySportIsCovered() {
        for sport in Sport.allCases {
            #expect(!WorkoutLibrary.templates(for: sport).isEmpty)
            #expect(WorkoutLibrary.templates(for: sport).allSatisfy { $0.sport == sport })
        }
    }

    @Test("Nothing in the library claims to be the athlete's own")
    func builtInsAreNotEditable() {
        #expect(WorkoutLibrary.all.allSatisfy { $0.source == .triLoop })
        #expect(WorkoutLibrary.all.allSatisfy { !$0.source.isEditable })
    }

    @Test("Every workout says what it is for and how hard it should feel")
    func templatesAreDescribed() {
        for template in WorkoutLibrary.all {
            #expect(!template.name.isEmpty)
            #expect(!template.purpose.isEmpty, "\(template.name) has no purpose")
            #expect(template.targetRPE != nil, "\(template.name) has no target effort")
        }
    }

    @Test("Recovery sessions are easier than interval sessions")
    func effortMatchesCategory() {
        let recovery = WorkoutLibrary.all.filter { $0.category == .recovery }
        let intervals = WorkoutLibrary.all.filter { $0.category == .intervals }

        #expect(!recovery.isEmpty && !intervals.isEmpty)
        #expect(recovery.allSatisfy { ($0.targetRPE?.upper ?? 10) <= 4 })
        #expect(intervals.allSatisfy { ($0.targetRPE?.lower ?? 0) >= 6 })
    }

    @Test("Every workout has a measurable total")
    func totalsAreAvailable() {
        for template in WorkoutLibrary.all {
            let hasTotal = template.totalDurationSeconds != nil || template.totalDistanceMeters != nil
            #expect(hasTotal, "\(template.name) has neither a duration nor a distance")
        }
    }

    @Test("A library workout becomes independent steps")
    func templatesInstantiate() throws {
        let template = try #require(WorkoutLibrary.running.first)

        let first = template.structure.makeSteps()
        let second = template.structure.makeSteps()

        #expect(!first.isEmpty)
        #expect(Set(first.map(\.id)).isDisjoint(with: Set(second.map(\.id))))
        #expect(WorkoutStructure(steps: first) == template.structure)
    }
}
