import Foundation
import SwiftData

/// Where a scheduled session came from.
///
/// §10.2.5: TriLoop must be able to tell what it prescribed from what the
/// athlete added, because "you followed your plan" is a different claim from
/// "you trained". Encoded explicitly rather than inferred from a title.
enum WorkoutOrigin: String, Codable, CaseIterable, Sendable {
    /// Built by the adaptive engine as part of the week.
    case generated
    /// Added by the athlete from the built-in library.
    case library
    /// Added by the athlete from a workout they created.
    case custom
    /// Recorded elsewhere and brought in without ever being prescribed.
    case imported

    /// Whether TriLoop asked for this session.
    ///
    /// Only a generated session counts toward how well the plan was followed;
    /// the rest are training the athlete chose to do (§10.2.10).
    var isPrescribedByTriLoop: Bool { self == .generated }

    var displayName: String {
        switch self {
        case .generated: "From your plan"
        case .library: "Added from the library"
        case .custom: "Your own workout"
        case .imported: "Recorded elsewhere"
        }
    }
}

/// An athlete-owned template, persisted.
///
/// §10.2.11: built-ins live in `WorkoutLibrary` as code because they are
/// identical on every device and change only with the app. Only what the
/// athlete authored needs storing.
///
/// The structure is held as one `Codable` value rather than a relationship to
/// `WorkoutStep`, so a template is never entangled with the workouts made from
/// it — editing one cannot reach into the other (§10.3.15).
@Model
final class StoredWorkoutTemplate {
    var id: UUID
    var sport: Sport
    var name: String
    var category: WorkoutCategory
    var purpose: String
    var structure: WorkoutStructure
    var targetRPE: RPERange?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sport: Sport,
        name: String,
        category: WorkoutCategory,
        purpose: String = "",
        structure: WorkoutStructure = WorkoutStructure(),
        targetRPE: RPERange? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sport = sport
        self.name = name
        self.category = category
        self.purpose = purpose
        self.structure = structure
        self.targetRPE = targetRPE
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension StoredWorkoutTemplate {
    /// Athlete templates are always `.athlete`; the source is not stored because
    /// storing it would allow a row claiming to be built in.
    var template: WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            sport: sport,
            name: name,
            category: category,
            purpose: purpose,
            structure: structure,
            targetRPE: targetRPE,
            source: .athlete
        )
    }

    convenience init(_ template: WorkoutTemplate, createdAt: Date = .now) {
        self.init(
            id: template.id,
            sport: template.sport,
            name: template.name,
            category: template.category,
            purpose: template.purpose,
            structure: template.structure,
            targetRPE: template.targetRPE,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    func apply(_ template: WorkoutTemplate, at date: Date = .now) {
        sport = template.sport
        name = template.name
        category = template.category
        purpose = template.purpose
        structure = template.structure
        targetRPE = template.targetRPE
        updatedAt = date
    }
}
