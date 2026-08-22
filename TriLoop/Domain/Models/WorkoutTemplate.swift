import Foundation

/// What a session is for, across all three sports.
///
/// Deliberately sport-neutral: "intervals" means the same thing in a pool as on
/// a bike, and a per-sport enum would be two dozen near-duplicate cases that
/// analysis would then have to collapse again.
enum WorkoutCategory: String, Codable, CaseIterable, Sendable {
    case easy
    case recovery
    case endurance
    case intervals
    case tempo
    case technique
    case long

    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .recovery: "Recovery"
        case .endurance: "Endurance"
        case .intervals: "Intervals"
        case .tempo: "Tempo"
        case .technique: "Technique"
        case .long: "Long"
        }
    }
}

/// Who authored a template.
///
/// §10.2.4: survives persistence, because a built-in cannot be edited in place
/// and an athlete's own workout can.
enum WorkoutTemplateSource: String, Codable, CaseIterable, Sendable {
    case triLoop
    case athlete

    var isEditable: Bool { self == .athlete }
}

/// A reusable session, with no date and no occurrence attached.
///
/// §10.2.1: distinct from `PlannedWorkout`, which is one actual scheduled
/// instance. A template is instantiated into a planned workout; the planned
/// workout then carries its own resolved prescription and never looks back at
/// the template again.
struct WorkoutTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var sport: Sport
    var name: String
    var category: WorkoutCategory
    /// One sentence on what the session is for, shown above the structure.
    var purpose: String
    var structure: WorkoutStructure
    var targetRPE: RPERange?
    var source: WorkoutTemplateSource

    init(
        id: UUID = UUID(),
        sport: Sport,
        name: String,
        category: WorkoutCategory,
        purpose: String = "",
        structure: WorkoutStructure,
        targetRPE: RPERange? = nil,
        source: WorkoutTemplateSource = .athlete
    ) {
        self.id = id
        self.sport = sport
        self.name = name
        self.category = category
        self.purpose = purpose
        self.structure = structure
        self.targetRPE = targetRPE
        self.source = source
    }

    var totalDurationSeconds: TimeInterval? { structure.totalDurationSeconds }
    var totalDistanceMeters: Double? { structure.totalDistanceMeters }
}

/// Why a template cannot be used as written.
enum WorkoutTemplateIssue: Equatable, Sendable {
    case missingName
    case noExecutableBlock
    case blockWithoutTarget(title: String)
    case nonPositiveDuration(title: String)
    case nonPositiveDistance(title: String)
    case invalidRepeatCount(title: String)
    case emptyRepeatBlock(title: String)
    /// A swim length that the athlete's pool cannot produce in whole lengths.
    case swimDistanceOffPoolLength(title: String, meters: Double)

    var message: String {
        switch self {
        case .missingName:
            "Give the workout a name."
        case .noExecutableBlock:
            "Add at least one block of work."
        case .blockWithoutTarget(let title):
            "\"\(title)\" needs a duration or a distance."
        case .nonPositiveDuration(let title):
            "\"\(title)\" needs a duration longer than zero."
        case .nonPositiveDistance(let title):
            "\"\(title)\" needs a distance longer than zero."
        case .invalidRepeatCount(let title):
            "\"\(title)\" needs to repeat at least twice."
        case .emptyRepeatBlock(let title):
            "\"\(title)\" has nothing to repeat."
        case .swimDistanceOffPoolLength(let title, let meters):
            "\(Int(meters)) m in \"\(title)\" is not a whole number of lengths."
        }
    }
}

/// §10.3.11: validation lives here rather than in the builder's view, so the
/// library, the builder and any future import all reject the same workouts.
enum WorkoutTemplateValidator {

    static func issues(in template: WorkoutTemplate, poolLengthMeters: Double? = nil) -> [WorkoutTemplateIssue] {
        var issues: [WorkoutTemplateIssue] = []

        if template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.missingName)
        }
        if !template.structure.hasExecutableBlock {
            issues.append(.noExecutableBlock)
        }

        for block in template.structure.blocks {
            issues.append(
                contentsOf: self.issues(
                    in: block,
                    sport: template.sport,
                    poolLengthMeters: poolLengthMeters
                )
            )
        }

        return issues
    }

    static func isValid(_ template: WorkoutTemplate, poolLengthMeters: Double? = nil) -> Bool {
        issues(in: template, poolLengthMeters: poolLengthMeters).isEmpty
    }

    private static func issues(
        in block: WorkoutBlock,
        sport: Sport,
        poolLengthMeters: Double?
    ) -> [WorkoutTemplateIssue] {
        var issues: [WorkoutTemplateIssue] = []

        if let seconds = block.durationSeconds, seconds <= 0 {
            issues.append(.nonPositiveDuration(title: block.title))
        }
        if let meters = block.distanceMeters, meters <= 0 {
            issues.append(.nonPositiveDistance(title: block.title))
        }

        if block.kind == .repeatBlock {
            if (block.repeatCount ?? 0) < 2 {
                issues.append(.invalidRepeatCount(title: block.title))
            }
            if block.children.isEmpty {
                issues.append(.emptyRepeatBlock(title: block.title))
            }
            for child in block.children {
                issues.append(contentsOf: self.issues(in: child, sport: sport, poolLengthMeters: poolLengthMeters))
            }
            return issues
        }

        // A repeat block is measured by its children, but everything else has
        // to say how long or how far, or the Watch has nothing to count.
        if block.durationSeconds == nil, block.distanceMeters == nil {
            issues.append(.blockWithoutTarget(title: block.title))
        }

        if sport == .swimming,
           let meters = block.distanceMeters,
           meters > 0,
           let poolLength = poolLengthMeters,
           poolLength > 0,
           meters.truncatingRemainder(dividingBy: poolLength) != 0 {
            issues.append(.swimDistanceOffPoolLength(title: block.title, meters: meters))
        }

        return issues
    }
}
