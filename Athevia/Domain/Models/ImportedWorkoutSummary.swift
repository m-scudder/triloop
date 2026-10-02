import Foundation
import SwiftData

/// Normalized record of a workout imported from any connected source.
///
/// The stored UUID column keeps its legacy name for SwiftData compatibility,
/// but the ingestion layer treats it as a provider-neutral import identity.
/// Source aliases live inside RecordedMetrics so adding Strava/Runna does not
/// require a schema migration.
@Model
final class ImportedWorkoutSummary {
    var id: UUID
    @Attribute(.unique) var healthKitUUID: UUID

    /// Provider-neutral name for the legacy persisted UUID column.
    var importID: UUID { healthKitUUID }

    var importAliases: [WorkoutImportAlias] {
        metrics?.importAliases ?? []
    }
    var sport: Sport
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval
    var distanceMeters: Double?
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var elevationAscendedMeters: Double?
    var swimmingLengths: Int?
    var swimmingStrokeCount: Double?
    var longestContinuousSwimMeters: Double?
    /// Extensible bag of sensor values. New metrics go in here rather than
    /// becoming columns, so the schema version does not move.
    ///
    /// Optional because SwiftData does not apply a Swift default to rows that
    /// were stored without the property: the generated getter casts whatever is
    /// there, and a non-optional type traps on the `nil`.
    var metrics: RecordedMetrics?
    var source: String?
    var importedAt: Date

    var workout: PlannedWorkout?

    init(
        id: UUID = UUID(),
        healthKitUUID: UUID,
        sport: Sport,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil,
        elevationAscendedMeters: Double? = nil,
        swimmingLengths: Int? = nil,
        swimmingStrokeCount: Double? = nil,
        longestContinuousSwimMeters: Double? = nil,
        metrics: RecordedMetrics? = nil,
        source: String? = nil,
        importedAt: Date = .now
    ) {
        self.id = id
        self.healthKitUUID = healthKitUUID
        self.sport = sport
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.elevationAscendedMeters = elevationAscendedMeters
        self.swimmingLengths = swimmingLengths
        self.swimmingStrokeCount = swimmingStrokeCount
        self.longestContinuousSwimMeters = longestContinuousSwimMeters
        self.metrics = metrics
        self.source = source
        self.importedAt = importedAt
    }

    convenience init(_ imported: ImportedWorkout, importedAt: Date = .now) {
        var recorded = imported.metrics
        recorded.recordImportAlias(imported.identity.alias)

        self.init(
            healthKitUUID: imported.importID,
            sport: imported.sport,
            startDate: imported.startDate,
            endDate: imported.endDate,
            duration: imported.duration,
            distanceMeters: imported.distanceMeters,
            averageHeartRate: imported.averageHeartRate,
            maximumHeartRate: imported.maximumHeartRate,
            elevationAscendedMeters: imported.elevationAscendedMeters,
            swimmingLengths: imported.swimmingLengths,
            swimmingStrokeCount: imported.swimmingStrokeCount,
            longestContinuousSwimMeters: imported.longestContinuousSwimMeters,
            metrics: recorded,
            source: imported.source,
            importedAt: importedAt
        )
    }

    var discipline: Discipline {
        (metrics?.multisportSegments.isEmpty == false) ? .multisport : sport.discipline
    }

    var imported: ImportedWorkout {
        let identity: WorkoutImportIdentity = {
            if let alias = importAliases.first {
                return WorkoutImportIdentity(
                    providerID: alias.providerID,
                    externalID: alias.externalID,
                    stableUUID: importID
                )
            }
            return .appleHealth(importID)
        }()

        return ImportedWorkout(
            identity: identity,
            sport: sport,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            elevationAscendedMeters: elevationAscendedMeters,
            swimmingLengths: swimmingLengths,
            swimmingStrokeCount: swimmingStrokeCount,
            longestContinuousSwimMeters: longestContinuousSwimMeters,
            metrics: metrics ?? RecordedMetrics(),
            source: source
        )
    }
}
