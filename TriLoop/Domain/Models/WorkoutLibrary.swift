import Foundation

/// The curated set of sessions TriLoop ships with.
///
/// §10.2.11: a domain fixture rather than persisted rows. Built-ins are
/// immutable and identical on every device, so storing them would mean
/// migrating copies of content that only ever changes with the app itself.
///
/// Identifiers are literal and permanent: a planned workout records where it
/// came from, and that reference has to survive an app update.
enum WorkoutLibrary {

    static var all: [WorkoutTemplate] { running + swimming + cycling }

    static func templates(for sport: Sport) -> [WorkoutTemplate] {
        switch sport {
        case .running: running
        case .swimming: swimming
        case .cycling: cycling
        }
    }

    static func template(id: UUID) -> WorkoutTemplate? {
        all.first { $0.id == id }
    }

    // MARK: - Running

    static let running: [WorkoutTemplate] = [
        WorkoutTemplate(
            id: id("2C7C1B10-0001-4000-A000-000000000001"),
            sport: .running,
            name: "Easy Run",
            category: .easy,
            purpose: "Build aerobic endurance with controlled effort.",
            structure: WorkoutStructure([
                .warmUp("Brisk walk", seconds: 300),
                .work("Easy running", seconds: 1_200, intensity: .easy),
                .coolDown("Easy walk", seconds: 300)
            ]),
            targetRPE: RPERange(3, 4),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0001-4000-A000-000000000002"),
            sport: .running,
            name: "Run / Walk",
            category: .easy,
            purpose: "Build running time without the impact of running throughout.",
            structure: WorkoutStructure([
                .warmUp("Brisk walk", seconds: 300),
                .repeating("Run / walk", times: 6, [
                    .work("Easy run", seconds: 120, intensity: .easy),
                    .recovery("Walk", seconds: 60)
                ]),
                .coolDown("Easy walk", seconds: 300)
            ]),
            targetRPE: RPERange(3, 4),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0001-4000-A000-000000000003"),
            sport: .running,
            name: "Recovery Run",
            category: .recovery,
            purpose: "Keep the legs moving without adding fatigue.",
            structure: WorkoutStructure([
                .work("Very easy running", seconds: 1_200, intensity: .veryEasy)
            ]),
            targetRPE: RPERange(2, 3),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0001-4000-A000-000000000004"),
            sport: .running,
            name: "Long Run",
            category: .long,
            purpose: "Extend how long you can keep going at an easy effort.",
            structure: WorkoutStructure([
                .warmUp("Brisk walk", seconds: 300),
                .work("Steady running", seconds: 3_000, intensity: .easy),
                .coolDown("Easy walk", seconds: 300)
            ]),
            targetRPE: RPERange(3, 5),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0001-4000-A000-000000000005"),
            sport: .running,
            name: "Tempo Run",
            category: .tempo,
            purpose: "Hold a comfortably hard effort you could sustain a little longer.",
            structure: WorkoutStructure([
                .warmUp("Easy jog", seconds: 600),
                .repeating("Tempo blocks", times: 3, [
                    .work("Tempo", seconds: 480, intensity: .moderate),
                    .recovery("Easy jog", seconds: 120)
                ]),
                .coolDown("Easy jog", seconds: 600)
            ]),
            targetRPE: RPERange(6, 7),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0001-4000-A000-000000000006"),
            sport: .running,
            name: "Intervals",
            category: .intervals,
            purpose: "Short, hard efforts with full recovery between them.",
            structure: WorkoutStructure([
                .warmUp("Easy jog", seconds: 600),
                .repeating("Intervals", times: 6, [
                    .work("Hard", seconds: 60, intensity: .hard),
                    .recovery("Easy jog", seconds: 120)
                ]),
                .coolDown("Easy jog", seconds: 600)
            ]),
            targetRPE: RPERange(8, 9),
            source: .triLoop
        )
    ]

    // MARK: - Swimming

    /// Distances are multiples of 50 m so a set is whole lengths in both a 25 m
    /// and a 50 m pool.
    static let swimming: [WorkoutTemplate] = [
        WorkoutTemplate(
            id: id("2C7C1B10-0002-4000-A000-000000000001"),
            sport: .swimming,
            name: "Technique Swim",
            category: .technique,
            purpose: "Short repeats with rest, so form holds all the way through.",
            structure: WorkoutStructure([
                .warmUp("Easy swim", meters: 200),
                .repeating("Breathing focus", times: 4, [
                    .work("Freestyle", meters: 50, intensity: .easy),
                    .recovery("Rest", seconds: 20)
                ]),
                .repeating("Relaxed freestyle", times: 4, [
                    .work("Freestyle", meters: 50, intensity: .easy),
                    .recovery("Rest", seconds: 20)
                ]),
                .coolDown("Easy swim", meters: 200)
            ]),
            targetRPE: RPERange(3, 4),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0002-4000-A000-000000000002"),
            sport: .swimming,
            name: "Easy Endurance",
            category: .endurance,
            purpose: "Time in the water at an effort you could hold all day.",
            structure: WorkoutStructure([
                .warmUp("Easy swim", meters: 100),
                .work("Continuous swim", meters: 400, intensity: .easy),
                .coolDown("Easy swim", meters: 100)
            ]),
            targetRPE: RPERange(3, 4),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0002-4000-A000-000000000003"),
            sport: .swimming,
            name: "Swim Intervals",
            category: .intervals,
            purpose: "Repeats at a firmer effort with enough rest to hold form.",
            structure: WorkoutStructure([
                .warmUp("Easy swim", meters: 200),
                .repeating("Main set", times: 6, [
                    .work("Firm freestyle", meters: 50, intensity: .moderate),
                    .recovery("Rest", seconds: 30)
                ]),
                .coolDown("Easy swim", meters: 200)
            ]),
            targetRPE: RPERange(6, 7),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0002-4000-A000-000000000004"),
            sport: .swimming,
            name: "Recovery Swim",
            category: .recovery,
            purpose: "Loosen off without asking anything of the session.",
            structure: WorkoutStructure([
                .work("Very easy swim", meters: 400, intensity: .veryEasy)
            ]),
            targetRPE: RPERange(2, 3),
            source: .triLoop
        )
    ]

    // MARK: - Cycling

    static let cycling: [WorkoutTemplate] = [
        WorkoutTemplate(
            id: id("2C7C1B10-0003-4000-A000-000000000001"),
            sport: .cycling,
            name: "Easy Ride",
            category: .easy,
            purpose: "Ride steadily, not hard.",
            structure: WorkoutStructure([
                .warmUp("Spin up", seconds: 600),
                .work("Easy riding", seconds: 1_800, intensity: .easy),
                .coolDown("Spin down", seconds: 600)
            ]),
            targetRPE: RPERange(3, 4),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0003-4000-A000-000000000002"),
            sport: .cycling,
            name: "Endurance Ride",
            category: .endurance,
            purpose: "A longer steady ride that builds aerobic base.",
            structure: WorkoutStructure([
                .warmUp("Spin up", seconds: 600),
                .work("Steady riding", seconds: 3_600, intensity: .easy),
                .coolDown("Spin down", seconds: 600)
            ]),
            targetRPE: RPERange(3, 5),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0003-4000-A000-000000000003"),
            sport: .cycling,
            name: "Recovery Ride",
            category: .recovery,
            purpose: "Easy spinning to help the legs come back.",
            structure: WorkoutStructure([
                .work("Very easy spinning", seconds: 1_800, intensity: .veryEasy)
            ]),
            targetRPE: RPERange(2, 3),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0003-4000-A000-000000000004"),
            sport: .cycling,
            name: "Tempo Ride",
            category: .tempo,
            purpose: "Sustained blocks at an effort you can just hold a conversation through.",
            structure: WorkoutStructure([
                .warmUp("Spin up", seconds: 600),
                .repeating("Tempo blocks", times: 3, [
                    .work("Tempo", seconds: 480, intensity: .moderate),
                    .recovery("Easy spinning", seconds: 180)
                ]),
                .coolDown("Spin down", seconds: 600)
            ]),
            targetRPE: RPERange(6, 7),
            source: .triLoop
        ),
        WorkoutTemplate(
            id: id("2C7C1B10-0003-4000-A000-000000000005"),
            sport: .cycling,
            name: "Bike Intervals",
            category: .intervals,
            purpose: "Hard efforts with equal recovery between them.",
            structure: WorkoutStructure([
                .warmUp("Spin up", seconds: 600),
                .repeating("Intervals", times: 5, [
                    .work("Hard", seconds: 180, intensity: .hard),
                    .recovery("Easy spinning", seconds: 180)
                ]),
                .coolDown("Spin down", seconds: 600)
            ]),
            targetRPE: RPERange(7, 8),
            source: .triLoop
        )
    ]

    /// Literal identifiers. A malformed one is a typo, and the library tests
    /// fail loudly rather than the app quietly shipping a random identity.
    private static func id(_ string: String) -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Malformed built-in template identifier: \(string)")
        }
        return uuid
    }
}

// MARK: - Block shorthands

extension WorkoutBlock {
    static func warmUp(_ title: String, seconds: TimeInterval? = nil, meters: Double? = nil) -> WorkoutBlock {
        WorkoutBlock(
            kind: .warmUp,
            title: title,
            durationSeconds: seconds,
            distanceMeters: meters,
            targetIntensity: .veryEasy
        )
    }

    static func coolDown(_ title: String, seconds: TimeInterval? = nil, meters: Double? = nil) -> WorkoutBlock {
        WorkoutBlock(
            kind: .cooldown,
            title: title,
            durationSeconds: seconds,
            distanceMeters: meters,
            targetIntensity: .veryEasy
        )
    }

    static func work(
        _ title: String,
        seconds: TimeInterval? = nil,
        meters: Double? = nil,
        intensity: TargetIntensity? = nil
    ) -> WorkoutBlock {
        WorkoutBlock(
            kind: .work,
            title: title,
            durationSeconds: seconds,
            distanceMeters: meters,
            targetIntensity: intensity
        )
    }

    static func recovery(_ title: String, seconds: TimeInterval? = nil, meters: Double? = nil) -> WorkoutBlock {
        WorkoutBlock(
            kind: .recovery,
            title: title,
            durationSeconds: seconds,
            distanceMeters: meters
        )
    }

    static func repeating(_ title: String, times: Int, _ children: [WorkoutBlock]) -> WorkoutBlock {
        WorkoutBlock(kind: .repeatBlock, title: title, repeatCount: times, children: children)
    }
}
